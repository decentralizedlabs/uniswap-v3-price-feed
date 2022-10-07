// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";
import { console2 } from "forge-std/console2.sol";
import { PriceFeed } from "../contracts/PriceFeed.sol";
import { UniswapV3Factory } from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";
import { UniswapV3Pool } from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";

uint24 constant poolFee = 3000;
address constant a1 = address(1);

contract BaseTest is DSTestPlus {
  PriceFeed priceFeed;
  UniswapV3Factory uniswapV3Factory;
  UniswapV3Pool pool;
  ERC20Mock token1;
  ERC20Mock token2;

  function setUp() public {
    uniswapV3Factory = new UniswapV3Factory();
    priceFeed = new PriceFeed(address(uniswapV3Factory));
    token1 = new ERC20Mock();
    token2 = new ERC20Mock();

    // pool = UniswapV3Pool(
    //   uniswapV3Factory.createPool(address(token1), address(token2), poolFee)
    // );
    // pool.initialize(2 << 96);
    // token1.approve(address(pool), type(uint256).max);
    // token2.approve(address(pool), type(uint256).max);
    // // ...
  }

  // tickspacing = 60

  function testGetQuoteNoPool() public {
    uint256 quote = priceFeed.getQuote(
      1e18,
      address(token1),
      address(token2),
      1800
    );
    assertEq(quote, 0);
  }

  function testUpdatePool() public {
    priceFeed.updatePool(address(token1), address(token2));
  }
}
