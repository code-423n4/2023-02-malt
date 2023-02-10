// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IMiningService {
  function withdrawAccountRewards(uint256 poolId, uint256 amount) external;

  function balanceOfRewards(address account, uint256 poolId)
    external
    view
    returns (uint256);

  function earned(address account, uint256 poolId)
    external
    view
    returns (uint256);

  function onBond(
    address account,
    uint256 poolId,
    uint256 amount
  ) external;

  function onUnbond(
    address account,
    uint256 poolId,
    uint256 amount
  ) external;

  function withdrawRewardsForAccount(
    address account,
    uint256 poolId,
    uint256 amount
  ) external;
}
