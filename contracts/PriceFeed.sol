// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/IPriceFeed.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {PoolAddress} from "./utils/PoolAddress.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

/**
 * @title PriceFeed
 * @author jacopo.eth <jacopo@slice.so>
 *
 * @notice Price feed based on Uniswap V3 TWAP oracles.
 */
contract PriceFeed is IPriceFeed {
  /// =================================
  /// ============ Events =============
  /// =================================

  /// Emitted when a pool is updated
  event PoolUpdated(PoolData pool);

  /// =================================
  /// ======= Immutable Storage =======
  /// =================================

  /// TWAP interval used when updating pools
  uint32 public constant UPDATE_INTERVAL = 30 minutes;
  /// UPDATE_INTERVAL multiplied by 2**160
  uint192 private constant UPDATE_INTERVAL_X160 = uint192(UPDATE_INTERVAL) << 160;
  /// UPDATE_INTERVAL formatted to secondsAgo array
  uint32[] private UPDATE_SECONDS_AGO = [UPDATE_INTERVAL, 0];
  /// UniswapV3Pool possible fee amounts
  uint24[] private FEES = [10000, 3000, 500, 100];
  /// Max cardinality value when updating pools via `getUpdatedPool` or `getQuoteAndUpdatePool`
  /// @dev Max useful cardinality for 30-min TWAPs, based on a max of 5 observation per minute.
  uint16 public MAX_CARDINALITY = 150;
  /// UniswapV3Factory contract address
  address public immutable uniswapV3Factory;

  /// =================================
  /// ============ Storage ============
  /// =================================

  /// Mapping from currency to PoolData
  mapping(address => mapping(address => PoolData)) public pools;

  /// =================================
  /// ========== Constructor ==========
  /// =================================

  constructor(address uniswapV3Factory_) {
    uniswapV3Factory = uniswapV3Factory_;
  }

  /// =================================
  /// =========== Functions ===========
  /// =================================

  /**
   * @notice Retrieves pool given tokenA and tokenB regardless of order.
   * @param tokenA Address of one of the ERC20 token contract in the pool
   * @param tokenB Address of the other ERC20 token contract in the pool
   * @return pool address, fee and last edit timestamp.
   */
  function getPool(address tokenA, address tokenB) public view returns (PoolData memory pool) {
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

    pool = pools[token0][token1];
  }

  /**
   * @notice Get the time-weighted quote of `quoteToken` received in exchange for a `baseAmount`
   * of `baseToken`, from the pool with highest liquidity, based on a `secondsAgo` twap interval.
   * @param baseAmount Amount of baseToken to be converted
   * @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
   * @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
   * @param secondsAgo Number of seconds in the past from which to calculate the time-weighted quote
   * @return quoteAmount Equivalent amount of ERC20 token for baseAmount
   *
   * Note: If a pool does not exist or a valid quote is not returned execution will not revert and
   * `quoteAmount` will be 0.
   */
  function getQuote(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    uint32 secondsAgo
  ) public view returns (uint256 quoteAmount) {
    address pool = getPool(baseToken, quoteToken).poolAddress;

    if (pool != address(0)) {
      // Get spot price
      if (secondsAgo == 0) {
        // Get sqrtPriceX96 from slot0
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        quoteAmount = _getQuoteAtSqrtPriceX96(sqrtPriceX96, baseAmount, baseToken, quoteToken);
      }
      // Get TWAP price
      else {
        int24 arithmeticMeanTick = _getArithmeticMeanTick(pool, secondsAgo);
        quoteAmount = OracleLibrary.getQuoteAtTick(
          arithmeticMeanTick,
          baseAmount,
          baseToken,
          quoteToken
        );
      }
    }
  }

  /**
   * @notice Retrieves pool given tokenA and tokenB regardless of order, and updates pool if necessary.
   * @param tokenA Address of one of the ERC20 token contract in the pool
   * @param tokenB Address of the other ERC20 token contract in the pool
   * @param updateInterval Seconds after which a pool is considered stale and an update is triggered
   * @param cardinalityIncrease The increase amount in cardinality to trigger during update in a pool
   * if current value < MAX_CARDINALITY
   * @return pool address, fee and last edit timestamp
   *
   * Note: Set updateInterval to 0 to always trigger an update, or to block.timestamp to only update if a pool
   * has not been stored yet.
   */
  function getUpdatedPool(
    address tokenA,
    address tokenB,
    uint256 updateInterval,
    uint8 cardinalityIncrease
  ) public returns (PoolData memory pool) {
    // Shortcircuit the case where we need to update
    if (updateInterval == 0) {
      (pool, , ) = updatePool(tokenA, tokenB, cardinalityIncrease);
      return pool;
    }

    pool = getPool(tokenA, tokenB);

    // If no pool is stored or updateInterval has passed since lastUpdatedTimestamp
    if (
      pool.poolAddress == address(0) ||
      pool.lastUpdatedTimestamp + updateInterval <= block.timestamp
    ) {
      (pool, , ) = updatePool(tokenA, tokenB, cardinalityIncrease);
    }
  }

  /**
   * @notice Get the time-weighted quote of `quoteToken`, and updates the pool when there is no pool stored.
   * @param baseAmount Amount of baseToken to be converted
   * @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
   * @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
   * @param secondsAgo Number of seconds in the past from which to calculate the time-weighted quote
   * @param updateInterval Seconds after which a pool is considered stale and an update is triggered
   * @param cardinalityIncrease The increase in cardinality to trigger in a pool if current value < MAX_CARDINALITY
   * @return quoteAmount Equivalent amount of ERC20 token for baseAmount
   *
   * Note: If a pool does not exist or a valid quote is not returned execution will not revert and
   * `quoteAmount` will be 0.
   * Note: Set updateInterval to 0 to always trigger an update, or to block.timestamp to only update if a pool
   * has not been stored yet.
   */
  function getQuoteAndUpdatePool(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    uint32 secondsAgo,
    uint256 updateInterval,
    uint8 cardinalityIncrease
  ) public returns (uint256 quoteAmount) {
    (
      PoolData memory pool,
      int56[] memory tickCumulatives,
      uint160 sqrtPriceX96
    ) = _getUpdatedPoolWithTicks(baseToken, quoteToken, updateInterval, cardinalityIncrease);

    // If pool exists
    if (pool.poolAddress != address(0)) {
      // Get spot price
      if (secondsAgo == 0) {
        // If sqrtPriceX96 was not returned from `_getUpdatedPoolWithTicks`
        if (sqrtPriceX96 == 0) {
          // Get sqrtPriceX96 from slot0
          (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool.poolAddress).slot0();
        }

        quoteAmount = _getQuoteAtSqrtPriceX96(sqrtPriceX96, baseAmount, baseToken, quoteToken);
      }
      // Get TWAP price
      else {
        int24 arithmeticMeanTick;

        // If _getUpdatedPoolWithTicks returned non null tickCumulatives
        if (tickCumulatives[0] != tickCumulatives[1]) {
          // Calculate arithmeticMeanTick from tickCumulatives
          int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
          arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
          // Always round to negative infinity
          if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0))
            arithmeticMeanTick--;
        } else {
          arithmeticMeanTick = _getArithmeticMeanTick(pool.poolAddress, secondsAgo);
        }

        quoteAmount = OracleLibrary.getQuoteAtTick(
          arithmeticMeanTick,
          baseAmount,
          baseToken,
          quoteToken
        );
      }
    }
  }

  /**
   * @notice Updates stored pool with the most traded one in the last 30 minutes.
   * The most traded pool is considered to be the one with the highest TWAL.
   * @param tokenA Address of one of the ERC20 token contract in the pool
   * @param tokenB Address of the other ERC20 token contract in the pool
   * @param cardinalityIncrease The increase amount in cardinality to trigger during update in a pool
   * if current value < MAX_CARDINALITY
   * @return highestLiquidityPool Pool with the highest harmonicMeanLiquidity
   * @return tickCumulatives Cumulative tick values as of 30 minutes from the current block timestamp
   * @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
   */
  function updatePool(
    address tokenA,
    address tokenB,
    uint8 cardinalityIncrease
  )
    public
    returns (
      PoolData memory highestLiquidityPool,
      int56[] memory tickCumulatives,
      uint160 sqrtPriceX96
    )
  {
    // Order token addresses
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

    // Get highest liquidity pool
    (highestLiquidityPool, tickCumulatives, sqrtPriceX96) = _getHighestLiquidityPool(
      token0,
      token1,
      cardinalityIncrease
    );

    /// Update pool in storage with `highestLiquidityPool`
    /// @dev New value should be stored even if highestPool = currentPool to update `lastUpdatedTimestamp`.
    pools[token0][token1] = highestLiquidityPool;
    emit PoolUpdated(highestLiquidityPool);
  }

  /**
   * @notice Gets the pool with the highest harmonic liquidity.
   * @param token0 Address of the first ERC20 token contract in the pool
   * @param token1 Address of the second ERC20 token contract in the pool
   * @param cardinalityIncrease The increase amount in cardinality to trigger during update in a pool
   * if current value < MAX_CARDINALITY
   * @return highestLiquidityPool Pool with the highest harmonicMeanLiquidity
   * @return tickCumulatives Cumulative tick values as of 30 minutes from the current block timestamp
   * @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
   */
  function _getHighestLiquidityPool(
    address token0,
    address token1,
    uint8 cardinalityIncrease
  )
    private
    returns (
      PoolData memory highestLiquidityPool,
      int56[] memory tickCumulatives,
      uint160 sqrtPriceX96
    )
  {
    // Add reference for highest liquidity
    uint256 highestLiquidity;

    // Add reference for values used in loop
    address poolAddress;
    uint256 harmonicMeanLiquidity;

    for (uint256 i; i < 4; ) {
      // Compute pool address
      poolAddress = PoolAddress.computeAddress(
        uniswapV3Factory,
        PoolAddress.PoolKey(token0, token1, FEES[i])
      );

      // If pool has been deployed
      if (poolAddress.code.length != 0) {
        // Get 30-min harmonic mean liquidity
        (harmonicMeanLiquidity, tickCumulatives) = _getHarmonicMeanLiquidity(poolAddress);

        // If liquidity is higher than the previously stored one
        if (harmonicMeanLiquidity > highestLiquidity) {
          // Update reference values except pool cardinality
          highestLiquidity = harmonicMeanLiquidity;
          highestLiquidityPool = PoolData(poolAddress, FEES[i], uint48(block.timestamp), 0);
        }
      }

      unchecked {
        ++i;
      }
    }

    // If there is a pool to update
    if (highestLiquidityPool.poolAddress != address(0)) {
      // Update observation cardinality of `highestLiquidityPool`
      (sqrtPriceX96, , , highestLiquidityPool.lastUpdatedCardinality, , , ) = IUniswapV3Pool(
        highestLiquidityPool.poolAddress
      ).slot0();

      // If a cardinality increase is wanted and current cardinality < MAX_CARDINALITY
      if (
        cardinalityIncrease != 0 && highestLiquidityPool.lastUpdatedCardinality < MAX_CARDINALITY
      ) {
        // Increase cardinality and update value in reference pool
        // Does not overflow uint16 as MAX_CARDINALITY + type(uint8).max < uint(16).max
        unchecked {
          highestLiquidityPool.lastUpdatedCardinality += cardinalityIncrease;
          IUniswapV3Pool(highestLiquidityPool.poolAddress).increaseObservationCardinalityNext(
            highestLiquidityPool.lastUpdatedCardinality
          );
        }
      }
    }
  }

  /**
   * @notice Same as `getUpdatedPool` but also returns tickCumulatives if an update is triggered.
   * Used internally in `getQuoteAndUpdatePool` to avoid an unnecessary call to the pool.
   * @param tokenA Address of one of the ERC20 token contract in the pool
   * @param tokenB Address of the other ERC20 token contract in the pool
   * @param updateInterval Seconds after which a pool is considered stale and an update is triggered
   * @param cardinalityIncrease The increase amount in cardinality to trigger during update in a pool
   * if current value < MAX_CARDINALITY
   * @return pool address, fee and last edit timestamp
   * @return tickCumulatives Cumulative tick values as of 30 minutes from the current block timestamp
   * @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
   */
  function _getUpdatedPoolWithTicks(
    address tokenA,
    address tokenB,
    uint256 updateInterval,
    uint8 cardinalityIncrease
  )
    private
    returns (
      PoolData memory pool,
      int56[] memory tickCumulatives,
      uint160 sqrtPriceX96
    )
  {
    // Shortcircuit the case where we need to update
    if (updateInterval == 0) return updatePool(tokenA, tokenB, cardinalityIncrease);

    pool = getPool(tokenA, tokenB);

    // If no pool is stored or updateInterval has passed since lastUpdatedTimestamp
    if (
      pool.poolAddress == address(0) ||
      pool.lastUpdatedTimestamp + updateInterval <= block.timestamp
    ) {
      return updatePool(tokenA, tokenB, cardinalityIncrease);
    }
  }

  /**
   * @notice Same as `consult` in {OracleLibrary} but saves gas by not calculating `harmonicMeanLiquidity`.
   * @param pool Address of the pool that we want to observe
   * @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
   * @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp
   *
   * @dev Silently handles errors in `uniswapV3Pool.observe` to prevent reverts.
   */
  function _getArithmeticMeanTick(address pool, uint32 secondsAgo)
    private
    view
    returns (int24 arithmeticMeanTick)
  {
    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = secondsAgo;
    secondsAgos[1] = 0;

    // Call uniswapV3Pool.observe
    (bool success, bytes memory data) = pool.staticcall(
      abi.encodeWithSelector(0x883bdbfd, secondsAgos)
    );

    // If observe hasn't reverted
    if (success) {
      // Decode `tickCumulatives` from returned data
      (int56[] memory tickCumulatives, ) = abi.decode(data, (int56[], uint160[]));

      int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

      arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
      // Always round to negative infinity
      if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0))
        arithmeticMeanTick--;
    }
  }

  /**
   * @notice Same as `consult` in {OracleLibrary} but saves gas by not calculating `arithmeticMeanTick` and
   * defaulting to `UPDATE_INTERVAL` seconds ago.
   * @param pool Address of the pool that we want to observe
   * @return harmonicMeanLiquidity The harmonic mean liquidity from (block.timestamp - secondsAgo) to block.timestamp
   * @return tickCumulatives Cumulative tick values as of 30 minutes from the current block timestamp
   *
   * @dev Silently handles errors in `uniswapV3Pool.observe` to prevent reverts.
   */
  function _getHarmonicMeanLiquidity(address pool)
    private
    view
    returns (uint128 harmonicMeanLiquidity, int56[] memory tickCumulatives)
  {
    // Call uniswapV3Pool.observe
    (bool success, bytes memory data) = pool.staticcall(
      abi.encodeWithSelector(0x883bdbfd, UPDATE_SECONDS_AGO)
    );

    // If observe hasn't reverted
    if (success) {
      uint160[] memory secondsPerLiquidityCumulativeX128s;
      // Decode `tickCumulatives` and `secondsPerLiquidityCumulativeX128s` from returned data
      (tickCumulatives, secondsPerLiquidityCumulativeX128s) = abi.decode(
        data,
        (int56[], uint160[])
      );

      uint160 secondsPerLiquidityCumulativesDelta = secondsPerLiquidityCumulativeX128s[1] -
        secondsPerLiquidityCumulativeX128s[0];

      harmonicMeanLiquidity = uint128(
        UPDATE_INTERVAL_X160 / (uint192(secondsPerLiquidityCumulativesDelta) << 32)
      );
    }
  }

  /// @notice Reduced `getQuoteAtTick` logic which directly uses sqrtPriceX96
  /// @param sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
  /// @param baseAmount Amount of token to be converted
  /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
  /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
  /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
  function _getQuoteAtSqrtPriceX96(
    uint160 sqrtPriceX96,
    uint128 baseAmount,
    address baseToken,
    address quoteToken
  ) private pure returns (uint256 quoteAmount) {
    // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
    if (sqrtPriceX96 <= type(uint128).max) {
      uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
      quoteAmount = baseToken < quoteToken
        ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
        : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
    } else {
      uint256 ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
      quoteAmount = baseToken < quoteToken
        ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
        : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
    }
  }
}
