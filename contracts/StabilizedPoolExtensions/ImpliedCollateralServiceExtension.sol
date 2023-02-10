// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IImpliedCollateralService.sol";

/// @title Implied Collateral Service Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the ImpliedCollateralService
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract ImpliedCollateralServiceExtension {
  IImpliedCollateralService public impliedCollateralService;

  event SetImpliedCollateralService(address impliedCollataeralService);

  /// @notice Method for setting the address of the impliedCollateralService
  /// @param _impliedCollateralService The address of the ImpliedCollateralService instance
  /// @dev Only callable via the PoolUpdater contract
  function setImpliedCollateralService(address _impliedCollateralService)
    external
  {
    _accessControl();
    require(_impliedCollateralService != address(0), "Cannot use addr(0)");
    _beforeSetImpliedCollateralService(_impliedCollateralService);
    impliedCollateralService = IImpliedCollateralService(
      _impliedCollateralService
    );
    emit SetImpliedCollateralService(_impliedCollateralService);
  }

  function _beforeSetImpliedCollateralService(address _impliedCollateralService)
    internal
    virtual
  {}

  function _accessControl() internal virtual;
}
