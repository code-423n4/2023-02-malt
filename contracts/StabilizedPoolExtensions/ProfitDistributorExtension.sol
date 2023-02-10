// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IProfitDistributor.sol";

/// @title Profit Distributor Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the ProfitDistributor
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract ProfitDistributorExtension {
  IProfitDistributor public profitDistributor;

  event SetProfitDistributor(address profitDistributor);

  /// @notice Privileged method for setting the address of the profitDistributor
  /// @param _profitDistributor The contract address of the ProfitDistributor instance
  /// @dev Only callable via the PoolUpdater contract
  function setProfitDistributor(address _profitDistributor) external {
    _accessControl();
    require(_profitDistributor != address(0), "Cannot use addr(0)");
    _beforeSetProfitDistributor(_profitDistributor);
    profitDistributor = IProfitDistributor(_profitDistributor);
    emit SetProfitDistributor(_profitDistributor);
  }

  function _beforeSetProfitDistributor(address _profitDistributor)
    internal
    virtual
  {}

  function _accessControl() internal virtual;
}
