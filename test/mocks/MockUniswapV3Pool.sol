// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { UniswapV3Pool } from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";

contract MockUniswapV3Pool is UniswapV3Pool {
  constructor() UniswapV3Pool() {}
}
