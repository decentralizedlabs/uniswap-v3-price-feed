// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import { DSTestPlus } from "lib/solmate/src/test/utils/DSTestPlus.sol";
import { console2 } from "lib/forge-std/src/console2.sol";
import { PriceFeed } from "../contracts/PriceFeed.sol";

contract BaseTest is DSTestPlus {
  PriceFeed priceFeeds;
  address constant uniswapV3Factory =
    0x1F98431c8aD98523631AE4a59f267346ea31F984;

  function setUp() public {
    priceFeeds = new PriceFeed(uniswapV3Factory);
  }

  function testNoPool() public {
    uint256 quote = priceFeeds.getQuote(1e18, address(1), address(2), 1800);
    assertEq(quote, 0);
  }
}
