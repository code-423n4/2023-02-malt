// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IMaltDataLab.sol";

/// @title Malt Data Lab Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the MaltDataLab
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract DataLabExtension {
  IMaltDataLab public maltDataLab;

  event SetMaltDataLab(address maltDataLab);

  /// @notice Privileged method for setting the address of the maltDataLab
  /// @param _maltDataLab The contract address of the MaltDataLab instance
  /// @dev Only callable via the PoolUpdater contract
  function setMaltDataLab(address _maltDataLab) external {
    _accessControl();
    require(_maltDataLab != address(0), "Cannot use addr(0)");
    _beforeSetMaltDataLab(_maltDataLab);
    maltDataLab = IMaltDataLab(_maltDataLab);
    emit SetMaltDataLab(_maltDataLab);
  }

  function _beforeSetMaltDataLab(address _maltDataLab) internal virtual {}

  function _accessControl() internal virtual;
}
