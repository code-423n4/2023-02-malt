// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IDexHandler.sol";

/// @title Dex Handler Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the DexHandler
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract DexHandlerExtension {
  IDexHandler public dexHandler;

  event SetDexHandler(address dexHandler);

  /// @notice Privileged method for setting the address of the dexHandler
  /// @param _dexHandler The contract address of the DexHandler instance
  /// @dev Only callable via the PoolUpdater contract
  function setDexHandler(address _dexHandler) external {
    _accessControl();
    require(_dexHandler != address(0), "Cannot use addr(0)");
    _beforeSetDexHandler(_dexHandler);
    dexHandler = IDexHandler(_dexHandler);
    emit SetDexHandler(_dexHandler);
  }

  function _beforeSetDexHandler(address _dexHandler) internal virtual {}

  function _accessControl() internal virtual;
}
