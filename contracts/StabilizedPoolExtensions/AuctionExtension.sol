// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IAuction.sol";

/// @title Auction Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that need access to the Auction
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract AuctionExtension {
  IAuction public auction;

  event SetAuction(address auction);

  /// @notice Method for setting the address of the auction
  /// @param _auction The address of the Auction instance
  /// @dev Only callable via the PoolUpdater contract
  function setAuction(address _auction) external {
    _accessControl();
    require(_auction != address(0), "Cannot use addr(0)");
    _beforeSetAuction(_auction);
    auction = IAuction(_auction);
    emit SetAuction(_auction);
  }

  function _beforeSetAuction(address _auction) internal virtual {}

  function _accessControl() internal virtual;
}
