// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IStabilizerNode.sol";

/// @title Stabilizer Node Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the StabilizerNode
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract StabilizerNodeExtension {
  IStabilizerNode public stabilizerNode;

  event SetStablizerNode(address stabilizerNode);

  /// @notice Privileged method for setting the address of the stabilizerNode
  /// @param _stabilizerNode The contract address of the StabilizerNode instance
  /// @dev Only callable via the PoolUpdater contract
  function setStablizerNode(address _stabilizerNode) external {
    _accessControl();
    require(_stabilizerNode != address(0), "Cannot use addr(0)");
    _beforeSetStabilizerNode(_stabilizerNode);
    stabilizerNode = IStabilizerNode(_stabilizerNode);
    emit SetStablizerNode(_stabilizerNode);
  }

  function _beforeSetStabilizerNode(address _stabilizerNode) internal virtual {}

  function _accessControl() internal virtual;
}
