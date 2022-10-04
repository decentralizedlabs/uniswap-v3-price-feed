// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import "../structs/UniswapPoolInfo.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@paulrberg/contracts/math/PRBMath.sol";

contract PriceFeeds {
    /// ============ Network-specific storage ============

    // MAINNET
    // AggregatorV3Interface private constant ethPriceFeed =
    //     AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    // address private constant _uniswapEthAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // GOERLI
    // AggregatorV3Interface private constant ethPriceFeed =
    //     AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
    // address private constant _uniswapEthAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    // RINKEBY
    AggregatorV3Interface private constant ethPriceFeed =
        AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e);
    address private constant _uniswapEthAddress = 0xc778417E063141139Fce010982780140Aa0cD5Ab;

    /// ============ Immutable storage ============

    // UniswapV3Factory contract interface
    IUniswapV3Factory private constant _uniswapV3Factory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2^128
    int24 internal constant MAX_TICK = 887272;

    function _getPool(address currency) internal view returns (address pool) {
        // if (poolInfo.lastEdited < block.timestamp + 1) {
        //     pool = poolInfo.poolAddress;
        // } else {
        // Get 0.3% ETH pool
        pool = _uniswapV3Factory.getPool(currency, _uniswapEthAddress, 3000);
        // If inexistent, get 1% ETH pool
        if (pool == address(0))
            pool = _uniswapV3Factory.getPool(currency, _uniswapEthAddress, 10000);
        // if (pool == address(0)) poolInfo = (pool, block.timestamp);
        // }
    }

    /** @notice Given a currency and baseWeiPrice, calculates the price of a currency.
     * Derived from Uniswap v3-periphery OracleLibrary.
     * @param currency Address of an ERC20 token contract used as the quoteAmount denomination
     * @param weiPrice Amount of wei to be converted
     * @param twapInterval Twap interval used to calculate the quote
     * @return currencyPrice Equivalent amount of ERC20 token for weiPrice
     */
    function _getCurrencyPrice(
        address currency,
        // address poolInfo,
        uint256 weiPrice,
        int16 twapInterval
    ) public view returns (uint256 currencyPrice) {
        // Get Uniswap pool
        address pool = _getPool(currency);

        if (pool != address(0)) {
            // uint256 currencyDecimals = IERC20Metadata(currency).decimals();
            uint256 sqrtPriceX96;

            // Spot Price
            if (twapInterval == 0) {
                // Get current price from pool (square root, scaled by 2^96)
                (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
            }
            // TWAP
            else {
                // Get tick assuming that twapInterval > 0
                uint32[] memory secondsAgos = new uint32[](2);
                secondsAgos[0] = uint16(twapInterval);
                (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);

                int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

                int24 arithmeticMeanTick = int24(tickCumulativesDelta / twapInterval);
                // Always round to negative infinity
                if (tickCumulativesDelta < 0 && (tickCumulativesDelta % twapInterval != 0)) {
                    arithmeticMeanTick--;
                }

                // Derive price from tick
                sqrtPriceX96 = _getSqrtRatioAtTick(arithmeticMeanTick);
            }

            // Calculate currencyPrice with better precision if it doesn't overflow when multiplied by itself
            if (sqrtPriceX96 <= type(uint128).max) {
                uint256 sqrtPriceX192 = sqrtPriceX96 * sqrtPriceX96;
                currencyPrice = _uniswapEthAddress < currency
                    ? PRBMath.mulDiv(sqrtPriceX192, weiPrice, 1 << 192)
                    : PRBMath.mulDiv(1 << 192, weiPrice, sqrtPriceX192);
            } else {
                uint256 sqrtPriceX128 = PRBMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
                currencyPrice = _uniswapEthAddress < currency
                    ? PRBMath.mulDiv(sqrtPriceX128, weiPrice, 1 << 128)
                    : PRBMath.mulDiv(1 << 128, weiPrice, sqrtPriceX128);
            }
        }
    }

    /**
     * @notice Returns the latest ETH/USD price from ChainLink
     */
    function _getEthUsd() internal view returns (uint256) {
        (, int256 price, , , ) = ethPriceFeed.latestRoundData();
        return uint256(price);
    }

    /// @notice Calculates sqrt(1.0001^tick) * 2^96 -- see Uniswap TickMath.sol https://github.com/134dd3v/v3-core/blob/solc-0.8-support/contracts/libraries/TickMath.sol
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets (token1/token0)
    /// at the given tick
    function _getSqrtRatioAtTick(int24 tick) private pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(uint24(MAX_TICK)), "T");

        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
        // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
        // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
}
