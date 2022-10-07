// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { ERC20 } from "solmate/tokens/ERC20.sol";

contract ERC20Mock is ERC20 {
  constructor() ERC20("test", "test", 18) {
    _mint(address(1), 1e36);
  }
}
