// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import { PRBMath } from "lib/prb-math/contracts/PRBMath.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

/// @title Oracle library
/// @notice Provides functions to integrate with V3 pool oracle
/// Modified from original implementation to allow compiling with solidity >=0.8.0
/// - Used PRBMath instead of Uniswap/FullMath
/// - Cast uint32 variables to int64 when required
/// - Added `getSqrtRatioAtTick` from Uniswap/TickMath
/// - Updated function visibility to public
library OracleLibrary {
  /// @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
  /// @param pool Address of the pool that we want to observe
  /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
  /// @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp
  /// @return harmonicMeanLiquidity The harmonic mean liquidity from (block.timestamp - secondsAgo) to block.timestamp
  function consult(address pool, uint32 secondsAgo)
    public
    view
    returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
  {
    require(secondsAgo != 0, "BP");

    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = secondsAgo;
    secondsAgos[1] = 0;

    (
      int56[] memory tickCumulatives,
      uint160[] memory secondsPerLiquidityCumulativeX128s
    ) = IUniswapV3Pool(pool).observe(secondsAgos);

    int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
    uint160 secondsPerLiquidityCumulativesDelta = secondsPerLiquidityCumulativeX128s[
        1
      ] - secondsPerLiquidityCumulativeX128s[0];

    arithmeticMeanTick = int24(
      tickCumulativesDelta / int64(uint64(secondsAgo))
    );
    // Always round to negative infinity
    if (
      tickCumulativesDelta < 0 &&
      (tickCumulativesDelta % int64(uint64(secondsAgo)) != 0)
    ) arithmeticMeanTick--;

    // We are multiplying here instead of shifting to ensure that harmonicMeanLiquidity doesn't overflow uint128
    uint192 secondsAgoX160 = uint192(secondsAgo) * type(uint160).max;
    harmonicMeanLiquidity = uint128(
      secondsAgoX160 / (uint192(secondsPerLiquidityCumulativesDelta) << 32)
    );
  }

  /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
  /// @param tick Tick value used to calculate the quote
  /// @param baseAmount Amount of token to be converted
  /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
  /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
  /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
  function getQuoteAtTick(
    int24 tick,
    uint128 baseAmount,
    address baseToken,
    address quoteToken
  ) public pure returns (uint256 quoteAmount) {
    uint160 sqrtRatioX96 = _getSqrtRatioAtTick(tick);

    // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
    if (sqrtRatioX96 <= type(uint128).max) {
      uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
      quoteAmount = baseToken < quoteToken
        ? PRBMath.mulDiv(ratioX192, baseAmount, 1 << 192)
        : PRBMath.mulDiv(1 << 192, baseAmount, ratioX192);
    } else {
      uint256 ratioX128 = PRBMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
      quoteAmount = baseToken < quoteToken
        ? PRBMath.mulDiv(ratioX128, baseAmount, 1 << 128)
        : PRBMath.mulDiv(1 << 128, baseAmount, ratioX128);
    }
  }

  /// @notice Given a pool, it returns the number of seconds ago of the oldest stored observation
  /// @param pool Address of Uniswap V3 pool that we want to observe
  /// @return secondsAgo The number of seconds ago of the oldest observation stored for the pool
  function getOldestObservationSecondsAgo(address pool)
    public
    view
    returns (uint32 secondsAgo)
  {
    (
      ,
      ,
      uint16 observationIndex,
      uint16 observationCardinality,
      ,
      ,

    ) = IUniswapV3Pool(pool).slot0();
    require(observationCardinality > 0, "NI");

    (uint32 observationTimestamp, , , bool initialized) = IUniswapV3Pool(pool)
      .observations((observationIndex + 1) % observationCardinality);

    // The next index might not be initialized if the cardinality is in the process of increasing
    // In this case the oldest observation is always in index 0
    if (!initialized) {
      (observationTimestamp, , , ) = IUniswapV3Pool(pool).observations(0);
    }

    secondsAgo = uint32(block.timestamp) - observationTimestamp;
  }

  /// @notice Given a pool, it returns the tick value as of the start of the current block
  /// @param pool Address of Uniswap V3 pool
  /// @return The tick that the pool was in at the start of the current block
  function getBlockStartingTickAndLiquidity(address pool)
    public
    view
    returns (int24, uint128)
  {
    (
      ,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      ,
      ,

    ) = IUniswapV3Pool(pool).slot0();

    // 2 observations are needed to reliably calculate the block starting tick
    require(observationCardinality > 1, "NEO");

    // If the latest observation occurred in the past, then no tick-changing trades have happened in this block
    // therefore the tick in `slot0` is the same as at the beginning of the current block.
    // We don't need to check if this observation is initialized - it is guaranteed to be.
    (
      uint32 observationTimestamp,
      int56 tickCumulative,
      uint160 secondsPerLiquidityCumulativeX128,

    ) = IUniswapV3Pool(pool).observations(observationIndex);
    if (observationTimestamp != uint32(block.timestamp)) {
      return (tick, IUniswapV3Pool(pool).liquidity());
    }

    uint256 prevIndex = (uint256(observationIndex) +
      observationCardinality -
      1) % observationCardinality;
    (
      uint32 prevObservationTimestamp,
      int56 prevTickCumulative,
      uint160 prevSecondsPerLiquidityCumulativeX128,
      bool prevInitialized
    ) = IUniswapV3Pool(pool).observations(prevIndex);

    require(prevInitialized, "ONI");

    uint32 delta = observationTimestamp - prevObservationTimestamp;
    tick = int24((tickCumulative - prevTickCumulative) / int64(uint64(delta)));
    uint128 liquidity = uint128(
      (uint192(delta) * type(uint160).max) /
        (uint192(
          secondsPerLiquidityCumulativeX128 -
            prevSecondsPerLiquidityCumulativeX128
        ) << 32)
    );
    return (tick, liquidity);
  }

  /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2^128
  int24 internal constant MAX_TICK = 887272;

  /// @notice Calculates sqrt(1.0001^tick) * 2^96 -- see Uniswap TickMath.sol https://github.com/134dd3v/v3-core/blob/solc-0.8-support/contracts/libraries/TickMath.sol
  /// @dev Throws if |tick| > max tick
  /// @param tick The input tick for the above formula
  /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets (token1/token0)
  /// at the given tick
  function _getSqrtRatioAtTick(int24 tick)
    private
    pure
    returns (uint160 sqrtPriceX96)
  {
    uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
    require(absTick <= uint256(uint24(MAX_TICK)), "T");

    uint256 ratio = absTick & 0x1 != 0
      ? 0xfffcb933bd6fad37aa2d162d1a594001
      : 0x100000000000000000000000000000000;
    if (absTick & 0x2 != 0)
      ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
    if (absTick & 0x4 != 0)
      ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
    if (absTick & 0x8 != 0)
      ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
    if (absTick & 0x10 != 0)
      ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
    if (absTick & 0x20 != 0)
      ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
    if (absTick & 0x40 != 0)
      ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
    if (absTick & 0x80 != 0)
      ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
    if (absTick & 0x100 != 0)
      ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
    if (absTick & 0x200 != 0)
      ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
    if (absTick & 0x400 != 0)
      ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
    if (absTick & 0x800 != 0)
      ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
    if (absTick & 0x1000 != 0)
      ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
    if (absTick & 0x2000 != 0)
      ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
    if (absTick & 0x4000 != 0)
      ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
    if (absTick & 0x8000 != 0)
      ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
    if (absTick & 0x10000 != 0)
      ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
    if (absTick & 0x20000 != 0)
      ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
    if (absTick & 0x40000 != 0)
      ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
    if (absTick & 0x80000 != 0)
      ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

    if (tick > 0) ratio = type(uint256).max / ratio;

    // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
    // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
    // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
    sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
  }
}
