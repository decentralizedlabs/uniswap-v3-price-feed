// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./structs/UniswapPoolInfo.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

contract PriceFeeds {
  /// =================================
  /// ======= Immutable Storage =======
  /// =================================

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

  function getPool(address baseToken, address quoteToken)
    public
    view
    returns (address pool)
  {
    // if (poolInfo.lastEdited < block.timestamp + 1) {
    //     pool = poolInfo.poolAddress;
    // } else {
    // Get 0.3% ETH pool
    pool = uniswapV3Factory.getPool(quoteToken, baseToken, 3000);
    // If inexistent, get 1% ETH pool
    if (pool == address(0))
      pool = uniswapV3Factory.getPool(quoteToken, baseToken, 10000);
    // if (pool == address(0)) poolInfo = (pool, block.timestamp);
    // }
  }

  /** @notice Given a currency and baseWeiPrice, calculates the price of a currency.
   * Derived from Uniswap v3-periphery OracleLibrary.
   * @param baseAmount Amount of token to be converted
   * @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
   * @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
   * @param secondsAgo Twap interval used to calculate the quote
   * @return quoteAmount Equivalent amount of ERC20 token for weiPrice
   */
  function getCurrencyPrice(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    uint32 secondsAgo
  ) public view returns (uint256 quoteAmount) {
    (address token0, address token1) = baseToken < quoteToken
      ? (baseToken, quoteToken)
      : (quoteToken, baseToken);

    address pool = pools[token0][token1].poolAddress;

    if (pool != address(0)) {
      (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) = OracleLibrary
        .consult(pool, secondsAgo);

      quoteAmount = OracleLibrary.getQuoteAtTick(
        arithmeticMeanTick,
        baseAmount,
        baseToken,
        quoteToken
      );
    }
  }
}
