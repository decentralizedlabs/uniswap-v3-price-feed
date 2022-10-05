// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import "./structs/UniswapPoolInfo.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

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
  mapping(address => mapping(address => UniswapPoolInfo)) public _pools;

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
   * @param baseToken Address of an ERC20 token contract used as the quoteAmount denomination
   * @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
   * @param baseAmount Amount of wei to be converted
   * @param secondsAgo Twap interval used to calculate the quote
   * @return quoteAmount Equivalent amount of ERC20 token for weiPrice
   */
  function _getCurrencyPrice(
    address baseToken,
    address quoteToken,
    uint128 baseAmount,
    uint32 secondsAgo
  ) public view returns (uint256 quoteAmount) {
    (address token0, address token1) = baseToken < quoteToken
      ? (baseToken, quoteToken)
      : (quoteToken, baseToken);

    address pool = _pools[token0][token1].poolAddress;

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
