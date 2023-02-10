// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/ILiquidityExtension.sol";

/// @title Liquidity Extension Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the LiquidityExtension
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract LiquidityExtensionExtension {
  ILiquidityExtension public liquidityExtension;

  event SetLiquidityExtension(address liquidityExtension);

  /// @notice Method for setting the address of the liquidityExtension
  /// @param _liquidityExtension The contract address of the LiquidityExtension instance
  /// @dev Only callable via the PoolUpdater contract
  function setLiquidityExtension(address _liquidityExtension) external {
    _accessControl();
    require(_liquidityExtension != address(0), "Cannot use addr(0)");
    _beforeSetLiquidityExtension(_liquidityExtension);
    liquidityExtension = ILiquidityExtension(_liquidityExtension);
    emit SetLiquidityExtension(_liquidityExtension);
  }

  function _beforeSetLiquidityExtension(address _liquidityExtension)
    internal
    virtual
  {}

  function _accessControl() internal virtual;
}
