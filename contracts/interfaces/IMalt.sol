// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IMalt {
  function balanceOf(address account) external view returns (uint256);

  function transfer(address recipient, uint256 amount) external returns (bool);

  function allowance(address owner, address spender)
    external
    view
    returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  function mint(address to, uint256 amount) external;

  function burn(address from, uint256 amount) external;

  function proposeNewVerifierManager(address) external;

  function acceptManagerRole() external;

  function addMinter(address) external;

  function addBurner(address) external;

  function removeMinter(address) external;

  function removeBurner(address) external;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}
