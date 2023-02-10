// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IAuctionStartController {
  function checkForStart() external view returns (bool);
}
