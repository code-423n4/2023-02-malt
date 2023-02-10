// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "forge-std/Test.sol";
import "../../contracts/Token/Malt.sol";
import "../../contracts/Token/TransferService.sol";
import "../../contracts/Repository.sol";

interface CheatCodes {
  function addr(uint256) external returns (address);
}

contract MaltTest is Test {
  Malt malt;
  TransferService transferService;
  MaltRepository repository;

  address user1 = vm.addr(1);
  address timelock = vm.addr(2);
  address initialAdmin = vm.addr(3);
  address globalIC = vm.addr(3);
  address manager = vm.addr(4);

  function setUp() public {
    repository = new MaltRepository(initialAdmin);
    transferService = new TransferService(
      address(repository),
      initialAdmin,
      initialAdmin
    );
    malt = new Malt(
      "Malt",
      "Malt",
      address(repository),
      address(transferService),
      initialAdmin
    );
    vm.prank(initialAdmin);
    address[] memory admins = new address[](1);
    admins[0] = initialAdmin;
    repository.setupContracts(
      timelock,
      admins,
      address(malt),
      address(1),
      address(transferService),
      address(1),
      address(1)
    );
  }

  function testInitialSetup(bytes32 seed, uint256 amount) public {
    vm.assume(amount < 100);
    address[] memory minters = new address[](amount);
    address[] memory burners = new address[](amount);
    for (uint256 i = 0; i < amount; i++) {
      minters[i] = address(
        bytes20(keccak256(abi.encodePacked(seed, "minter", i)))
      );
      burners[i] = address(
        bytes20(keccak256(abi.encodePacked(seed, "burner", i)))
      );
    }

    vm.prank(user1);
    vm.expectRevert("Only deployer");
    malt.setupContracts(globalIC, manager, minters, burners);

    vm.prank(initialAdmin);
    malt.setupContracts(globalIC, manager, minters, burners);

    for (uint256 i = 0; i < amount; i++) {
      vm.prank(minters[i]);
      malt.mint(minters[i], amount);
      assertEq(malt.balanceOf(minters[i]), amount);
    }

    for (uint256 i = 0; i < amount; i++) {
      vm.prank(minters[i]);
      malt.mint(burners[i], amount);
      assertEq(malt.balanceOf(burners[i]), amount);

      vm.prank(burners[i]);
      malt.burn(burners[i], amount);
      assertEq(malt.balanceOf(burners[i]), 0);
    }
  }

  function testMint(uint256 amount) public {
    vm.prank(user1);
    vm.expectRevert("Must have monetary minter role");
    malt.mint(user1, amount);

    vm.prank(timelock);
    malt.mint(user1, amount);
    assertEq(malt.balanceOf(user1), amount);
  }

  function testBurn(uint256 amountMint, uint256 amountBurn) public {
    vm.assume(amountMint > amountBurn);

    vm.prank(timelock);
    malt.mint(user1, amountMint);
    assertEq(malt.balanceOf(user1), amountMint);

    vm.prank(user1);
    vm.expectRevert("Must have monetary burner role");
    malt.burn(user1, amountBurn);

    vm.prank(timelock);
    malt.burn(user1, amountBurn);
    assertEq(malt.balanceOf(user1), (amountMint - amountBurn));
  }

  function testSetTransferService() public {
    vm.prank(user1);
    vm.expectRevert("Must have admin role");
    malt.setTransferService(user1);

    vm.prank(initialAdmin);
    malt.setTransferService(user1);
    assertEq(address(malt.transferService()), user1);
  }
}
