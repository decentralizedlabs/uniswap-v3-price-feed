// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import "forge-std/Script.sol";

import {PriceFeed} from "../contracts/PriceFeed.sol";
import {CREATE3Factory} from "create3-factory/CREATE3Factory.sol";

contract DeployScript is Script {
  function run() public returns (PriceFeed priceFeed) {
    address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    CREATE3Factory create3Factory = CREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    bytes32 salt = keccak256(bytes(vm.envString("SALT")));
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    vm.startBroadcast(deployerPrivateKey);

    priceFeed = PriceFeed(
      create3Factory.deploy(
        salt,
        bytes.concat(type(PriceFeed).creationCode, abi.encode(uniswapV3Factory))
      )
    );

    // priceFeed = new PriceFeed(uniswapV3Factory); // alt deploy when CREATE3 is not available

    vm.stopBroadcast();
  }
}
