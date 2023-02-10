// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ITransferVerification {
  function verifyTransfer(
    address,
    address,
    uint256
  )
    external
    view
    returns (
      bool,
      string memory,
      address,
      bytes memory
    );
}
