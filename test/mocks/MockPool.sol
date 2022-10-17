// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockPool {
  struct Slot0 {
    // the current price
    uint160 sqrtPriceX96;
    // the current tick
    int24 tick;
    // the most-recently updated index of the observations array
    uint16 observationIndex;
    // the current maximum number of observations that are being stored
    uint16 observationCardinality;
    // the next maximum number of observations to store, triggered in observations.write
    uint16 observationCardinalityNext;
    // the current protocol fee as a percentage of the swap fee taken on withdrawal
    // represented as an integer denominator (1/x)%
    uint8 feeProtocol;
    // whether the pool is locked
    bool unlocked;
  }
  Slot0 public slot0;

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

  function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external {
    // uint16 observationCardinalityNextOld = slot0.observationCardinalityNext; // for the event
    // uint16 observationCardinalityNextNew = observations.grow(
    //   observationCardinalityNextOld,
    //   observationCardinalityNext
    // );
    slot0.observationCardinalityNext = observationCardinalityNext;
    // if (observationCardinalityNextOld != observationCardinalityNextNew)
    //   emit IncreaseObservationCardinalityNext(
    //     observationCardinalityNextOld,
    //     observationCardinalityNextNew
    //   );
  }
}
