// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockPool {
  function observe(uint32[] calldata)
    external
    pure
    returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
  {
    int56[] memory a = new int56[](2);
    a[0] = 11510369842120;
    a[1] = 11510369434720;

    uint160[] memory b = new uint160[](2);
    b[0] = 4394094107204170683664807090433694295550448945;
    b[1] = 4394094107204170683664807220887586463231635652;

    return (a, b);
  }
}
