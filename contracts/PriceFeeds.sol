// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/IPriceFeeds.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract PriceFeeds is IPriceFeeds {
  /// =================================
  /// ======= Immutable Storage =======
  /// =================================

  // UniswapV3Pool possible fee amounts
  uint24[] private fees = [10000, 3000, 500, 100];
  // UniswapV3Factory contract interface
  IUniswapV3Factory public immutable uniswapV3Factory;

  /// =================================
  /// ============ Storage ============
  /// =================================

  /// Mapping from currency to UniswapPoolInfo
  mapping(address => mapping(address => UniswapPoolInfo)) public pools;

  /// =================================
  /// ========== Constructor ==========
  /// =================================
  constructor(address uniswapV3Factory_) {
    uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
  }

  /** @notice Given a currency and baseWeiPrice, calculates the price of a currency.
   * Derived from Uniswap v3-periphery OracleLibrary.
   * @param baseAmount Amount of token to be converted
   * @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
   * @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
   * @param secondsAgo Twap interval used to calculate the quote
   * @return quoteAmount Equivalent amount of ERC20 token for weiPrice
   */
  function getQuote(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    uint32 secondsAgo
  ) public view returns (uint256 quoteAmount) {
    address pool = getPool(baseToken, quoteToken).poolAddress;

    if (pool != address(0)) {
      int24 arithmeticMeanTick = getArithmeticMeanTick(pool, secondsAgo);

      quoteAmount = OracleLibrary.getQuoteAtTick(
        arithmeticMeanTick,
        baseAmount,
        baseToken,
        quoteToken
      );
    }
  }

  /** @notice Updates the `mainPool` in storage with the one having the highest `harmonicMeanLiquidity`.
   * @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
   * @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
   */
  function updatePool(address baseToken, address quoteToken) external {
    // Get current saved pool
    UniswapPoolInfo memory currentPool = getPool(baseToken, quoteToken);

    UniswapPoolInfo memory highestPool;
    uint128 highestLiquidity;
    uint24[] memory fees_ = fees;
    address pool;
    for (uint256 i; i < fees_.length; ) {
      pool = uniswapV3Factory.getPool(baseToken, quoteToken, fees_[i]);
      uint128 harmonicMeanLiquidity = getHarmonicMeanLiquidity(pool, 1800);

      if (harmonicMeanLiquidity > highestLiquidity) {
        highestLiquidity = harmonicMeanLiquidity;
        highestPool = UniswapPoolInfo(pool, fees_[i], uint48(block.timestamp));
      }

      unchecked {
        ++i;
      }
    }

    if (highestPool.poolAddress != currentPool.poolAddress) {
      (address token0, address token1) = baseToken < quoteToken
        ? (baseToken, quoteToken)
        : (quoteToken, baseToken);

      pools[token0][token1] = highestPool;
    }
  }

  /** @notice Retrieves pool given baseToken and quoteToken.
   * @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
   * @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
   * @return pool address, fee and last edit timestamp.
   */
  function getPool(address baseToken, address quoteToken)
    public
    view
    returns (UniswapPoolInfo memory pool)
  {
    (address token0, address token1) = baseToken < quoteToken
      ? (baseToken, quoteToken)
      : (quoteToken, baseToken);

    pool = pools[token0][token1];
  }

  /// @notice Same as `consult` in {OracleLibrary} but saves gas by not calculating `harmonicMeanLiquidity`.
  /// @param pool Address of the pool that we want to observe
  /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
  /// @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp
  function getArithmeticMeanTick(address pool, uint32 secondsAgo)
    private
    view
    returns (int24 arithmeticMeanTick)
  {
    require(secondsAgo != 0, "BP");

    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = secondsAgo;
    secondsAgos[1] = 0;

    (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
      secondsAgos
    );

    int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

    arithmeticMeanTick = int24(
      tickCumulativesDelta / int56(uint56(secondsAgo))
    );
    // Always round to negative infinity
    if (
      tickCumulativesDelta < 0 &&
      (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)
    ) arithmeticMeanTick--;
  }

  /// @notice Same as `consult` in {OracleLibrary} but saves gas by not calculating `arithmeticMeanTick`.
  /// @param pool Address of the pool that we want to observe
  /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
  /// @return harmonicMeanLiquidity The harmonic mean liquidity from (block.timestamp - secondsAgo) to block.timestamp
  function getHarmonicMeanLiquidity(address pool, uint32 secondsAgo)
    private
    view
    returns (uint128 harmonicMeanLiquidity)
  {
    require(secondsAgo != 0, "BP");

    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = secondsAgo;
    secondsAgos[1] = 0;

    (, uint160[] memory secondsPerLiquidityCumulativeX128s) = IUniswapV3Pool(
      pool
    ).observe(secondsAgos);

    uint160 secondsPerLiquidityCumulativesDelta = secondsPerLiquidityCumulativeX128s[
        1
      ] - secondsPerLiquidityCumulativeX128s[0];

    // We are multiplying here instead of shifting to ensure that harmonicMeanLiquidity doesn't overflow uint128
    uint192 secondsAgoX160 = uint192(secondsAgo) * type(uint160).max;
    harmonicMeanLiquidity = uint128(
      secondsAgoX160 / (uint192(secondsPerLiquidityCumulativesDelta) << 32)
    );
  }
}
