// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";

/// @title AbstractTransferVerification
/// @author 0xScotch <scotch@malt.money>
/// @notice Implements a single method that can block a particular transfer
abstract contract AbstractTransferVerification is StabilizedPoolUnit {
  constructor(
    address timelock,
    address initialAdmin,
    address poolFactory
  ) StabilizedPoolUnit(timelock, initialAdmin, poolFactory) {}

  function verifyTransfer(
    address from,
    address to,
    uint256 amount
  )
    external
    virtual
    returns (
      bool,
      string memory,
      address,
      bytes memory
    )
  {
    return (true, "", address(0), "");
  }
}
