// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { UniswapV3Factory } from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";

contract MockUniswapV3Factory is UniswapV3Factory {
  constructor() UniswapV3Factory() {}
}
