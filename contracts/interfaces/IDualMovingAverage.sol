// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IDualMovingAverage {
  function getValue() external view returns (uint256, uint256);

  function getValueWithLookback(uint256 _lookbackTime)
    external
    view
    returns (uint256, uint256);

  function getLiveSample()
    external
    view
    returns (
      uint64,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    );

  function update(uint256 newValue, uint256 newValueTwo) external;
}
