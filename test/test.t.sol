// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import { DSTestPlus } from "lib/solmate/src/test/utils/DSTestPlus.sol";
import { PriceFeed } from "../contracts/PriceFeed.sol";

contract BaseTest is DSTestPlus {
  PriceFeed priceFeeds;
  address constant uniswapV3Factory = address(20);

  function setUp() public {
    priceFeeds = new PriceFeed(uniswapV3Factory);
  }

  function testNoPool() public {
    uint256 quote = priceFeeds.getQuote(1e18, address(1), address(2), 1800);
    assertEq(quote, 0);
  }
}
