// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/ISwingTrader.sol";

/// @title Swing Trader Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the SwingTrader
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract SwingTraderExtension {
  ISwingTrader public swingTrader;

  event SetSwingTrader(address swingTrader);

  /// @notice Method for setting the address of the swingTrader
  /// @param _swingTrader The contract address of the SwingTrader instance
  /// @dev Only callable via the PoolUpdater contract
  function setSwingTrader(address _swingTrader) external {
    _accessControl();
    require(_swingTrader != address(0), "Cannot use addr(0)");
    _beforeSetSwingTrader(_swingTrader);
    swingTrader = ISwingTrader(_swingTrader);
    emit SetSwingTrader(_swingTrader);
  }

  function _beforeSetSwingTrader(address _swingTrader) internal virtual {}

  function _accessControl() internal virtual;
}
