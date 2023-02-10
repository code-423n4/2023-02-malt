// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../../contracts/Token/TransferService.sol";
import "./MaltTest.sol";

contract TransferServiceTest is MaltTest {
  address user1 = vm.addr(1);
  address user2 = vm.addr(2);
  address initialAdmin = vm.addr(4);
  address testPool = vm.addr(5);
  address mockPool =
    address(bytes20(keccak256(abi.encodePacked("some randomness"))));

  function setUp() public {
    transferService = new TransferService(
      address(repository),
      initialAdmin,
      initialAdmin
    );
  }

  function testAddVerifier() public {
    vm.prank(user1);
    vm.expectRevert("Must have verifier manager role");
    transferService.addVerifier(user1, testPool);

    vm.prank(user2);
    vm.expectRevert("Must have verifier manager role");
    transferService.addVerifier(user1, testPool);

    vm.prank(initialAdmin);
    transferService.addVerifier(user1, testPool);
    assertEq(transferService.numberOfVerifiers(), 1);
  }

  function testRemoveVerifier() public {
    vm.startPrank(initialAdmin);
    transferService.addVerifier(user1, testPool);
    transferService.addVerifier(user2, testPool);
    vm.stopPrank();

    vm.prank(user1);
    vm.expectRevert("Must have verifier manager role");
    transferService.removeVerifier(user1);

    vm.prank(user2);
    vm.expectRevert("Must have verifier manager role");
    transferService.removeVerifier(user1);

    assertEq(transferService.numberOfVerifiers(), 2);
    vm.prank(initialAdmin);
    transferService.removeVerifier(user1);
    assertEq(transferService.numberOfVerifiers(), 1);
  }

  function testDuplicateVerifier() public {
    vm.startPrank(initialAdmin);
    assertEq(transferService.numberOfVerifiers(), 0);
    transferService.addVerifier(user1, testPool);
    assertEq(transferService.numberOfVerifiers(), 1);
    vm.expectRevert("Address already exists");
    transferService.addVerifier(user1, testPool);
    assertEq(transferService.numberOfVerifiers(), 1);
  }

  function testVerifyTransferAndCall() public {
    bytes memory code = address(transferService).code;
    vm.etch(mockPool, code);
    vm.startPrank(initialAdmin);
    transferService.addVerifier(user1, mockPool);

    // Failure because user2 is not verified
    vm.deal(user1, 2 ether);
    vm.mockCall(
      mockPool,
      abi.encodeWithSelector(
        TransferService.verifyTransfer.selector,
        abi.encode(user1, user1, 1 ether)
      ),
      abi.encode(false, "User2 is not verified", user1, 1 ether)
    );
    (bool success, string memory str) = transferService.verifyTransferAndCall(
      user1,
      user2,
      1 ether
    );
    //assertEq(success, false);
    //assertEq(str, "");

    // Success
    transferService.addVerifier(user2, mockPool);
    vm.deal(user1, 2 ether);
    vm.mockCall(
      mockPool,
      abi.encodeWithSelector(
        TransferService.verifyTransfer.selector,
        abi.encode(user1, user2, 1 ether)
      ),
      abi.encode(true, "", user1, 1 ether)
    );
    (bool _success, string memory _str) = transferService.verifyTransferAndCall(
      user1,
      user2,
      1 ether
    );
    assertEq(success, true);
    assertEq(str, "");
  }
}
