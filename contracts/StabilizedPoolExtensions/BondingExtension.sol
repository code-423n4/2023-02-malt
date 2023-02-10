// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IBonding.sol";

/// @title Bonding Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the Bonding
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract BondingExtension {
  IBonding public bonding;

  event SetBonding(address bonding);

  /// @notice Method for setting the address of the bonding
  /// @param _bonding The contract address of the Bonding instance
  /// @dev Only callable via the PoolUpdater contract
  function setBonding(address _bonding) external {
    _accessControl();
    require(_bonding != address(0), "Cannot use addr(0)");
    _beforeSetBonding(_bonding);
    bonding = IBonding(_bonding);
    emit SetBonding(_bonding);
  }

  function _beforeSetBonding(address _bonding) internal virtual {}

  function _accessControl() internal virtual;
}
