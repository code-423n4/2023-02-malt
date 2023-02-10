// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IBondExtension {
  function onBond(
    address,
    uint256,
    uint256
  ) external;

  function onUnbond(
    address,
    uint256,
    uint256
  ) external;
}
