// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IPriceFeed {
  function getPool(address baseToken, address quoteToken) external;
}
