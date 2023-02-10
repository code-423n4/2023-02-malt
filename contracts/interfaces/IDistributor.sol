// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IDistributor {
  function totalDeclaredReward() external view returns (uint256);

  function declareReward(uint256 amount) external;

  function bondedValue() external view returns (uint256);

  function decrementRewards(uint256 amount) external;
}

interface IVestingDistributor is IDistributor {
  function vest() external;

  function forfeit(uint256 amount) external;

  function focalID() external view returns (uint256);

  function getAllFocalUnvestedBps() external view returns (uint256, uint256);

  function getFocalUnvestedBps(uint256) external view returns (uint256);

  function getCurrentlyVested() external view returns (uint256);
}
