// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/ISwingTrader.sol";

/// @title Swing Trader Manager Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the SwingTrader
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract SwingTraderManagerExtension {
  ISwingTrader public swingTraderManager;

  event SetSwingTraderManager(address swingTraderManager);

  /// @notice Method for setting the address of the swingTraderManager
  /// @param _swingTraderManager The contract address of the SwingTraderManager instance
  /// @dev Only callable via the PoolUpdater contract
  function setSwingTraderManager(address _swingTraderManager) external {
    _accessControl();
    require(_swingTraderManager != address(0), "Cannot use addr(0)");
    _beforeSetSwingTraderManager(_swingTraderManager);
    swingTraderManager = ISwingTrader(_swingTraderManager);
    emit SetSwingTraderManager(_swingTraderManager);
  }

  function _beforeSetSwingTraderManager(address _swingTraderManager)
    internal
    virtual
  {}

  function _accessControl() internal virtual;
}
