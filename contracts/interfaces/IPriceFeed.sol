// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../structs/PoolData.sol";

interface IPriceFeed {
  function uniswapV3Factory() external view returns (address uniswapV3Factory);

  function pools(address token0, address token1)
    external
    view
    returns (
      address poolAddress,
      uint24 fee,
      uint48 lastUpdatedTimestamp,
      uint16 lastUpdatedCardinality
    );

  function getPool(address tokenA, address tokenB) external view returns (PoolData memory pool);

  function getQuote(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    uint32 secondsAgo
  ) external view returns (uint256 quoteAmount);

  function getUpdatedPool(
    address tokenA,
    address tokenB,
    uint256 updateInterval,
    uint8 cardinalityIncrease
  )
    external
    returns (
      PoolData memory pool,
      int56[] memory tickCumulatives,
      uint160 sqrtPriceX96
    );

  function getQuoteAndUpdatePool(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    uint32 secondsAgo,
    uint256 updateInterval,
    uint8 cardinalityIncrease
  ) external returns (uint256 quoteAmount);

  function updatePool(
    address tokenA,
    address tokenB,
    uint8 cardinalityIncrease
  )
    external
    returns (
      PoolData memory highestLiquidityPool,
      int56[] memory tickCumulatives,
      uint160 sqrtPriceX96
    );
}
