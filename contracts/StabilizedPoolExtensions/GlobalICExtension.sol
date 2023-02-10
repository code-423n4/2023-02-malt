// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IGlobalImpliedCollateralService.sol";

/// @title Global Implied Collateral Service Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the GlobalImpliedCollateralService
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract GlobalICExtension {
  IGlobalImpliedCollateralService public globalIC;

  event SetGlobalIC(address globalIC);

  /// @notice Privileged method for setting the address of the globalIC
  /// @param _globalIC The contract address of the GlobalImpliedCollateralService instance
  /// @dev Only callable via the PoolUpdater contract
  function setGlobalIC(address _globalIC) external {
    _accessControl();
    require(_globalIC != address(0), "Cannot use addr(0)");
    _beforeSetGlobalIC(_globalIC);
    globalIC = IGlobalImpliedCollateralService(_globalIC);
    emit SetGlobalIC(_globalIC);
  }

  function _beforeSetGlobalIC(address _globalIC) internal virtual {}

  function _accessControl() internal virtual;
}
