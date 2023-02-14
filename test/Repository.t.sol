// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "forge-std/Test.sol";
import "./MaltTest.sol";
import "../contracts/Repository.sol";


contract RepositoryTest is Test {
  using stdStorage for StdStorage;

  MaltRepository repository;

  address admin = vm.addr(1);
  address timelock = vm.addr(2);
  address malt = vm.addr(3);
  address timekeeper = vm.addr(4);
  address transferService = vm.addr(5);
  address globalIC = vm.addr(6);
  address poolFactory = vm.addr(7);

  DecimalERC20 rewardToken;

  function setUp() public {
    repository = new MaltRepository(admin);
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

  function _setupContracts() internal {
    vm.prank(admin);
    address[] memory admins = new address[](1);
    admins[0] = admin;
    repository.setupContracts(
      timelock,
      admins,
      malt,
      timekeeper,
      transferService,
      globalIC,
      poolFactory 
    );
  }

  function testGetContract() public {
    _setupContracts();
    address localTimelock = repository.getContract("timelock");
    assertEq(localTimelock, timelock);
  }

  function testGrantRole() public {
    _setupContracts();
    string memory role = "SEND_IT_ROLE";
    bytes32 roleHash = keccak256(abi.encodePacked(role));

    bool valid = repository.checkRole(role);
    assertFalse(valid);

    vm.expectRevert();
    repository.addNewRole(roleHash);
    vm.prank(timelock);
    repository.addNewRole(roleHash);

    vm.expectRevert();
    repository.grantRole(roleHash, address(1234));
    vm.prank(timelock);
    repository.grantRole(roleHash, address(1234));

    valid = repository.checkRole(role);
    assertTrue(valid);
  }

  function testRemoveRole() public {
    _setupContracts();
    string memory role = "SEND_IT_ROLE";
    bytes32 roleHash = keccak256(abi.encodePacked(role));

    vm.startPrank(timelock);
    repository.addNewRole(roleHash);

    repository.grantRole(roleHash, address(1234));

    bool valid = repository.checkRole(role);
    assertTrue(valid);

    repository.removeRole(roleHash);
    vm.stopPrank();

    valid = repository.checkRole(role);
    assertFalse(valid);
  }

  function testSettingContracts(address newContract, address nextContract) public {
    vm.assume(newContract != nextContract);
    vm.assume(newContract != address(0));
    vm.assume(nextContract != address(0));
    _setupContracts();

    string memory contractName = "newContract";

    vm.expectRevert();
    repository.addNewContract(contractName, newContract);

    vm.prank(timelock);
    repository.addNewContract(contractName, newContract);

    vm.expectRevert("Contract exists");
    vm.prank(timelock);
    repository.addNewContract(contractName, newContract);

    address localContract = repository.getContract(contractName);
    assertEq(localContract, newContract);

    vm.expectRevert();
    repository.updateContract(contractName, nextContract);

    vm.prank(timelock);
    repository.updateContract(contractName, nextContract);

    localContract = repository.getContract(contractName);
    assertEq(localContract, nextContract);

    vm.expectRevert();
    repository.removeContract(contractName);

    vm.prank(timelock);
    repository.removeContract(contractName);

    localContract = repository.getContract(contractName);
    assertEq(localContract, address(0));
  }

  function testERC20Withdraw(uint256 amount, uint256 partialBps, address destination) public {
    amount = bound(amount, 100000, 2**100);
    partialBps = bound(partialBps, 1, 10000);
    vm.assume(destination != address(0));
    _setupContracts();

    amount = bound(amount, 1000, 2**100);
    partialBps = bound(partialBps, 0, 10000);

    mintRewardToken(address(repository), amount);

    uint256 initialBalance = rewardToken.balanceOf(destination);
    assertEq(initialBalance, 0);
    uint256 initialRepoBalance = rewardToken.balanceOf(address(repository));
    assertEq(initialRepoBalance, amount);

    vm.expectRevert();
    repository.partialWithdraw(address(rewardToken), destination, amount * partialBps / 10000);

    vm.prank(timelock);
    uint256 withdrawAmount = amount * partialBps / 10000;
    repository.partialWithdraw(address(rewardToken), destination, withdrawAmount);

    uint256 repoBalance = rewardToken.balanceOf(address(repository));
    assertEq(repoBalance, amount - withdrawAmount);

    uint256 finalBalance = rewardToken.balanceOf(destination);
    assertEq(finalBalance, withdrawAmount);

    vm.expectRevert();
    repository.emergencyWithdraw(address(rewardToken), destination);

    vm.prank(timelock);
    repository.emergencyWithdraw(address(rewardToken), destination);

    repoBalance = rewardToken.balanceOf(address(repository));
    assertEq(repoBalance, 0);

    finalBalance = rewardToken.balanceOf(destination);
    assertEq(finalBalance, amount);
  }

  function testNativeTokenWithdraw(uint256 amount, uint256 partialBps) public {
    amount = bound(amount, 100000, 2**100);
    partialBps = bound(partialBps, 1, 10000);
    _setupContracts();

    amount = bound(amount, 1000, 2**100);
    partialBps = bound(partialBps, 0, 10000);

    address destination = address(12345);

    vm.deal(address(repository), amount);

    uint256 initialBalance = destination.balance;
    assertEq(initialBalance, 0);
    uint256 initialRepoBalance = address(repository).balance;
    assertEq(initialRepoBalance, amount);

    vm.expectRevert();
    repository.partialWithdrawGAS(payable(destination), amount * partialBps / 10000);

    vm.prank(timelock);
    uint256 withdrawAmount = amount * partialBps / 10000;
    repository.partialWithdrawGAS(payable(destination), withdrawAmount);

    uint256 repoBalance = address(repository).balance;
    assertEq(repoBalance, amount - withdrawAmount);

    uint256 finalBalance = destination.balance;
    assertEq(finalBalance, withdrawAmount);

    vm.expectRevert();
    repository.emergencyWithdrawGAS(payable(destination));

    vm.prank(timelock);
    repository.emergencyWithdrawGAS(payable(destination));

    repoBalance = address(repository).balance;
    assertEq(repoBalance, 0);

    finalBalance = destination.balance;
    assertEq(finalBalance, amount);
  }

  function testGrantRoleMultiple() public {
    _setupContracts();
    string memory role = "SEND_IT_ROLE";
    bytes32 roleHash = keccak256(abi.encodePacked(role));

    vm.prank(timelock);
    repository.addNewRole(roleHash);

    address userOne = address(1234);
    address userTwo = address(1235);

    bool userOneHasRole = repository.hasRole(roleHash, userOne);
    bool userTwoHasRole = repository.hasRole(roleHash, userTwo);

    assertFalse(userOneHasRole);
    assertFalse(userTwoHasRole);

    address[] memory addresses = new address[](2);
    addresses[0] = userOne;
    addresses[1] = userTwo;

    vm.expectRevert();
    repository.grantRoleMultiple(roleHash, addresses);
    vm.prank(timelock);
    repository.grantRoleMultiple(roleHash, addresses);

    userOneHasRole = repository.hasRole(roleHash, userOne);
    userTwoHasRole = repository.hasRole(roleHash, userTwo);

    assertTrue(userOneHasRole);
    assertTrue(userTwoHasRole);
  }
}
