// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "forge-std/Test.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import "../contracts/Token/Malt.sol";
import "../contracts/Token/TransferService.sol";
import "../contracts/DataFeed/DualMovingAverage.sol";
import "../contracts/DataFeed/MaltDataLab.sol";
import "../contracts/Repository.sol";

contract DecimalERC20 is ERC20 {
  uint256 internal _decimals = 18;

  constructor(string memory name_, string memory symbol_)
    ERC20(name_, symbol_)
  {}

  function decimals() public view override returns (uint8) {
    return uint8(_decimals);
  }

  function setDecimals(uint256 __decimals) public {
    _decimals = __decimals;
  }
}

contract MaltTest is Test {
  using stdStorage for StdStorage;

  Malt malt;
  DecimalERC20 rewardToken;
  TransferService transferService;
  MaltRepository repository;

  address timelock = vm.addr(1);
  address admin = vm.addr(2);
  address user = vm.addr(3);
  address payable treasury = payable(vm.addr(4));

  uint256 _next = 5;

  constructor() {
    repository = new MaltRepository(admin);
    transferService = new TransferService(address(repository), admin, admin);
    malt = new Malt(
      "Malt",
      "Malt",
      address(repository),
      address(transferService),
      admin
    );
    rewardToken = new DecimalERC20("DAI Stablecoin", "DAI");
  }

  function mintRewardToken(address to, uint256 amount) public {
    uint256 slot = stdstore
      .target(address(rewardToken))
      .sig(rewardToken.balanceOf.selector)
      .with_key(to)
      .find();
    bytes32 loc = bytes32(slot);
    bytes32 mockedBalance = bytes32(abi.encode(amount));
    vm.store(address(rewardToken), loc, mockedBalance);
  }

  function mintMalt(address to, uint256 amount) public {
    vm.prank(timelock);
    malt.mint(to, amount);
  }

  function nextAddress() public returns (address next) {
    next = vm.addr(_next++);
  }

  function maltToRewardDecimals(uint256 amount, uint256 decimals)
    public
    returns (uint256 newAmount)
  {
    newAmount = amount;
    if (decimals < 18) {
      uint256 diff = 18 - decimals;
      newAmount = amount / (10**diff);
    } else if (decimals > 18) {
      uint256 diff = decimals - 18;
      newAmount = amount * (10**diff);
    }
  }

  function rewardToMaltDecimals(uint256 amount, uint256 decimals)
    public
    returns (uint256 newAmount)
  {
    newAmount = amount;
    if (decimals < 18) {
      uint256 diff = 18 - decimals;
      newAmount = amount * (10**diff);
    } else if (decimals > 18) {
      uint256 diff = decimals - 18;
      newAmount = amount / (10**diff);
    }
  }

  function assertHasMaltRole(
    address baseContract,
    bytes32 role,
    address testContract
  ) public {
    assertTrue(Permissions(baseContract).hasRole(role, testContract));
  }

  function assertNotHasMaltRole(
    address baseContract,
    bytes32 role,
    address testContract
  ) public {
    assertTrue(!Permissions(baseContract).hasRole(role, testContract));
  }
}
