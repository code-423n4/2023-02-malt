// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "../contracts/Staking/RewardMineBase.sol";
import "../contracts/Staking/Bonding.sol";
import "../contracts/Staking/MiningService.sol";
import "../contracts/Permissions.sol";
import "../contracts/Staking/AbstractRewardMine.sol";
import "./DeployedStabilizedPool.sol";

contract RewardMineBaseTest is DeployedStabilizedPool {
  using stdStorage for StdStorage;

  RewardMineBase rewardMineBase;
  address bonding;
  uint256 poolId = 1; // linearMine

  function setUp() public {
    StabilizedPool memory currentPool = getCurrentStabilizedPool();
    rewardMineBase = RewardMineBase(currentPool.staking.linearMine);
    bonding = currentPool.staking.bonding;
  }

  function testTotalBonded(uint256 amount) public {
    vm.mockCall(
      bonding,
      abi.encodeWithSelector(Bonding.totalBondedByPool.selector, poolId),
      abi.encode(amount)
    );
    assertEq(rewardMineBase.totalBonded(), amount);
  }

  function testBalanceBonded(uint64 amount) public {
    vm.mockCall(
      bonding,
      abi.encodeWithSelector(Bonding.balanceOfBonded.selector, poolId, user),
      abi.encode(amount)
    );

    assertEq(rewardMineBase.balanceOfBonded(user), amount);
  }

  function testDeposit(uint64 amount) public {
    vm.assume(amount > 0);
    uint256 slot = stdstore
      .target(address(lpToken))
      .sig(lpToken.balanceOf.selector)
      .with_key(user)
      .find();
    bytes32 loc = bytes32(slot);
    bytes32 mockedBalance = bytes32(abi.encode(amount));
    vm.store(address(lpToken), loc, mockedBalance);

    vm.startPrank(user);
    lpToken.approve(address(rewardMineBase), amount);

    vm.mockCall(
      bonding,
      abi.encodeWithSelector(Bonding.bondToAccount.selector),
      abi.encode(user, poolId, amount)
    );

    rewardMineBase.deposit(amount);
    vm.stopPrank();
  }

  function testSetBonding(address newBonding) public {
    assumeNoMaltContracts(newBonding);
    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    vm.prank(user);
    vm.expectRevert("Must have pool updater role");
    rewardMineBase.setBonding(newBonding);

    vm.prank(currentPool.updater);
    rewardMineBase.setBonding(newBonding);
  }
}
