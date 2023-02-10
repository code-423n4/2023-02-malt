// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IRewardThrottle.sol";

/// @title Reward Throttle Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the RewardThrottle
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract RewardThrottleExtension {
  IRewardThrottle public rewardThrottle;

  event SetRewardThrottle(address rewardThrottle);

  /// @notice Privileged method for setting the address of the rewardThrottle
  /// @param _rewardThrottle The contract address of the RewardThrottle instance
  /// @dev Only callable via the PoolUpdater contract
  function setRewardThrottle(address _rewardThrottle) external {
    _accessControl();
    require(_rewardThrottle != address(0), "Cannot use addr(0)");
    _beforeSetRewardThrottle(_rewardThrottle);
    rewardThrottle = IRewardThrottle(_rewardThrottle);
    emit SetRewardThrottle(_rewardThrottle);
  }

  function _beforeSetRewardThrottle(address _rewardThrottle) internal virtual {}

  function _accessControl() internal virtual;
}
