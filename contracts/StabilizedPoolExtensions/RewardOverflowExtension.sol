// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IOverflow.sol";

/// @title Reward Overflow Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the RewardOverflowPool
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract RewardOverflowExtension {
  IOverflow public overflowPool;

  event SetOverflowPool(address overflowPool);

  /// @notice Method for setting the address of the overflowPool
  /// @param _overflowPool The contract address of the RewardOverflowPool instance
  /// @dev Only callable via the PoolUpdater contract
  function setOverflowPool(address _overflowPool) external {
    _accessControl();
    require(_overflowPool != address(0), "Cannot use addr(0)");
    _beforeSetOverflowPool(_overflowPool);
    overflowPool = IOverflow(_overflowPool);
    emit SetOverflowPool(_overflowPool);
  }

  function _beforeSetOverflowPool(address _overflowPool) internal virtual {}

  function _accessControl() internal virtual;
}
