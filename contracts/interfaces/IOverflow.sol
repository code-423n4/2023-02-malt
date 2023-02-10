// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IOverflow {
  function requestCapital(uint256 amount)
    external
    returns (uint256 fulfilledAmount);

  function purchaseArbitrageTokens(uint256 maxAmount)
    external
    returns (uint256 remaining);

  function claim() external;

  function outstandingArbTokens() external view returns (uint256 outstanding);
}
