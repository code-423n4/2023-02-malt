// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../StabilityPod/PoolCollateral.sol";

interface IImpliedCollateralService {
  function collateralRatio() external view returns (uint256 icTotal);

  function syncGlobalCollateral() external;

  function getCollateralizedMalt()
    external
    view
    returns (PoolCollateral memory);

  function totalUsefulCollateral() external view returns (uint256);

  function swingTraderCollateralRatio() external view returns (uint256);
}
