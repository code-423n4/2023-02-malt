// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IAuction.sol";

interface IStabilizerNode {
  function stabilize() external;

  function auction() external view returns (IAuction);

  function priceAveragePeriod() external view returns (uint256);

  function upperStabilityThresholdBps() external view returns (uint256);

  function lowerStabilityThresholdBps() external view returns (uint256);

  function onlyStabilizeToPeg() external view returns (bool);

  function primedWindowData() external view returns (bool, uint256);
}
