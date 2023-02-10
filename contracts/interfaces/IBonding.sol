// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IBonding {
  function bond(uint256 poolId, uint256 amount) external;

  function bondToAccount(
    address account,
    uint256 poolId,
    uint256 amount
  ) external;

  function unbond(uint256 poolId, uint256 amount) external;

  function unbondAndBreak(
    uint256 poolId,
    uint256 amount,
    uint256 slippageBps
  ) external;

  function totalBonded() external view returns (uint256);

  function totalBondedByPool(uint256) external view returns (uint256);

  function balanceOfBonded(uint256 poolId, address account)
    external
    view
    returns (uint256);

  function averageBondedValue(uint256 epoch) external view returns (uint256);

  function stakeToken() external view returns (address);

  function stakeTokenDecimals() external view returns (uint256);

  function poolAllocations()
    external
    view
    returns (
      uint256[] memory poolIds,
      uint256[] memory allocations,
      address[] memory distributors
    );

  function valueOfBonded(uint256) external view returns (uint256);
}
