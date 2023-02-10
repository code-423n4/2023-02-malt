// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";

contract MintableERC20 is ERC20 {
  constructor(string memory name_, string memory symbol_)
    ERC20(name_, symbol_)
  {}

  function mint(address account, uint256 amount) external {
    _mint(account, amount);
  }
}
