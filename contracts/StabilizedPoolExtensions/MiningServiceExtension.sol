// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IMiningService.sol";

/// @title Mining Service Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the MiningService
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract MiningServiceExtension {
  IMiningService public miningService;

  event SetMiningService(address miningService);

  /// @notice Privileged method for setting the address of the miningService
  /// @param _miningService The contract address of the MiningService instance
  /// @dev Only callable via the PoolUpdater contract
  function setMiningService(address _miningService) external {
    _accessControl();
    require(_miningService != address(0), "Cannot use addr(0)");
    _beforeSetMiningService(_miningService);
    miningService = IMiningService(_miningService);
    emit SetMiningService(_miningService);
  }

  function _beforeSetMiningService(address _miningService) internal virtual {}

  function _accessControl() internal virtual;
}
