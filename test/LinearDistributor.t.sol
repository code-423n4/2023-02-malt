// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "../contracts/RewardSystem/LinearDistributor.sol";
import "./DeployedStabilizedPool.sol";

contract LinearDistributorTest is DeployedStabilizedPool {
  function setUp() public {
  }

  function testInitialSetup(address randomUser) public {
    assumeNoMaltContracts(randomUser);

    LinearDistributor linearDistributor = new LinearDistributor(
      timelock,
      address(repository),
      address(poolFactory)
    );

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    vm.prank(randomUser);
    vm.expectRevert("Only pool factory role");
    linearDistributor.setupContracts(
      currentPool.collateralToken,
      currentPool.staking.linearMine,
      currentPool.rewardSystem.rewardThrottle,
      currentPool.staking.forfeitHandler,
      currentPool.rewardSystem.vestingDistributor,
      pool
    );

    assertEq(address(linearDistributor.collateralToken()), address(0));
    assertEq(address(linearDistributor.rewardMine()), address(0));
    assertEq(address(linearDistributor.rewardThrottle()), address(0));
    assertEq(address(linearDistributor.forfeitor()), address(0));
    assertEq(address(linearDistributor.vestingDistributor()), address(0));
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.POOL_UPDATER_ROLE(),
        currentPool.updater
      ),
      false
    );
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.REWARDER_ROLE(),
        currentPool.rewardSystem.rewardThrottle
      ),
      false
    );
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.REWARD_MINE_ROLE(),
        currentPool.staking.linearMine
      ),
      false
    );

    vm.prank(address(poolFactory));
    linearDistributor.setupContracts(
      currentPool.collateralToken,
      currentPool.staking.linearMine,
      currentPool.rewardSystem.rewardThrottle,
      currentPool.staking.forfeitHandler,
      currentPool.rewardSystem.vestingDistributor,
      pool
    );

    assertEq(
      address(linearDistributor.collateralToken()),
      currentPool.collateralToken
    );
    assertEq(
      address(linearDistributor.rewardMine()),
      currentPool.staking.linearMine
    );
    assertEq(
      address(linearDistributor.rewardThrottle()),
      currentPool.rewardSystem.rewardThrottle
    );
    assertEq(
      address(linearDistributor.forfeitor()),
      currentPool.staking.forfeitHandler
    );
    assertEq(
      address(linearDistributor.vestingDistributor()),
      currentPool.rewardSystem.vestingDistributor
    );
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.POOL_UPDATER_ROLE(),
        currentPool.updater
      ),
      true
    );
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.REWARDER_ROLE(),
        currentPool.rewardSystem.rewardThrottle
      ),
      true
    );
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.REWARD_MINE_ROLE(),
        currentPool.staking.linearMine
      ),
      true
    );
  }

  // this event is needed for the below test
  event Forfeit(uint256 forfeited);

  function testDeclaringRewardsWithZeroBonded(
    address randomUser,
    uint32 rewarded
  ) public {
    vm.assume(rewarded != 0);
    assumeNoMaltContracts(randomUser);

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    LinearDistributor linearDistributor = LinearDistributor(
      currentPool.rewardSystem.linearDistributor
    );

    assertEq(linearDistributor.totalDeclaredReward(), 0);

    vm.prank(randomUser);
    vm.expectRevert("Only rewarder role");
    linearDistributor.declareReward(rewarded);

    vm.startPrank(currentPool.rewardSystem.rewardThrottle);

    // Try declaring 0 reward
    vm.expectRevert("Cannot declare 0 reward");
    linearDistributor.declareReward(0);

    // Declare reward without actually sending the capital
    vm.expectRevert("Insufficient balance");
    linearDistributor.declareReward(rewarded);

    mintRewardToken(address(linearDistributor), rewarded);

    // Should emit a Forfeit event with the entire balance forfeited
    vm.expectEmit(false, false, false, true);
    emit Forfeit(rewarded);

    linearDistributor.declareReward(rewarded);

    vm.stopPrank();

    assertEq(linearDistributor.totalDeclaredReward(), 0);
  }

  function testDeclaringLessThanRequiredRewards(
    address randomUser,
    uint64 rewarded,
    uint64 bondedValue,
    uint256 vestedDiffBps,
    uint256 decrementBps
  ) public {
    assumeNoMaltContracts(randomUser);
    vm.assume(rewarded != 0);
    vm.assume(bondedValue != 0);
    vestedDiffBps = bound(vestedDiffBps, 10000, 100000);
    decrementBps = bound(decrementBps, 1, 10000);

    // Make the two mines have the same bonded value
    uint256 vestingBondedValue = bondedValue;
    uint256 linearBondedValue = bondedValue;
    // Amount vested is always more than amount rewarded to the linear distributor
    // This means we never have a surplus on rewards and therefore never
    // touch the forfeit code paths
    uint256 currentlyVested = (rewarded * vestedDiffBps) / 10000;

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    // Mock some bonded balance
    vm.mockCall(
      currentPool.staking.linearMine,
      abi.encodeWithSelector(RewardMineBase.totalBonded.selector),
      abi.encode(1) // the exact value doesn't matter. It just needs to be non-zero
    );
    vm.mockCall(
      currentPool.rewardSystem.vestingDistributor,
      abi.encodeWithSelector(VestingDistributor.getCurrentlyVested.selector),
      abi.encode(currentlyVested)
    );
    vm.mockCall(
      currentPool.rewardSystem.vestingDistributor,
      abi.encodeWithSelector(VestingDistributor.bondedValue.selector),
      abi.encode(vestingBondedValue)
    );
    vm.mockCall(
      currentPool.staking.linearMine,
      abi.encodeWithSelector(RewardMineBase.valueOfBonded.selector),
      abi.encode(linearBondedValue)
    );

    LinearDistributor linearDistributor = LinearDistributor(
      currentPool.rewardSystem.linearDistributor
    );

    assertEq(linearDistributor.totalDeclaredReward(), 0);

    vm.prank(randomUser);
    vm.expectRevert("Only rewarder role");
    linearDistributor.declareReward(rewarded);

    vm.startPrank(currentPool.rewardSystem.rewardThrottle);

    // Try declaring 0 reward
    vm.expectRevert("Cannot declare 0 reward");
    linearDistributor.declareReward(0);

    // Declare reward without actually sending the capital
    vm.expectRevert("Insufficient balance");
    linearDistributor.declareReward(rewarded);

    mintRewardToken(address(linearDistributor), rewarded);
    linearDistributor.declareReward(rewarded);

    vm.stopPrank();

    // Total declared is always the amount actual sent
    // Due to the setup of this test there is never any surplus so all rewarded also gets distributed
    assertEq(linearDistributor.totalDeclaredReward(), rewarded);
    assertEq(rewardToken.balanceOf(currentPool.staking.linearMine), rewarded);
    assertEq(
      RewardMineBase(currentPool.staking.linearMine).totalReleasedReward(),
      rewarded
    );

    uint256 decrementBy = (rewarded * decrementBps) / 10000;
    uint256 afterDecrement = rewarded - decrementBy;

    vm.prank(randomUser);
    vm.expectRevert("Only reward mine");
    linearDistributor.decrementRewards(decrementBy);

    vm.prank(currentPool.staking.linearMine);
    linearDistributor.decrementRewards(decrementBy);

    assertEq(linearDistributor.totalDeclaredReward(), afterDecrement);
  }

  function testDeclaringSurplusRewards(
    address randomUser,
    uint64 rewarded,
    uint64 bondedValue,
    uint256 vestedDiffBps
  ) public {
    assumeNoMaltContracts(randomUser);
    vm.assume(rewarded != 0);
    vm.assume(bondedValue != 0);
    vestedDiffBps = bound(vestedDiffBps, 1, 5000);

    // Make the two mines have the same bonded value
    uint256 vestingBondedValue = bondedValue;
    uint256 linearBondedValue = bondedValue;
    // Amount vested is always less than amount rewarded to the linear distributor
    // This means we always have a surplus on rewards and therefore should retain some
    // behind in the contract
    uint256 currentlyVested = (rewarded * vestedDiffBps) / 10000;
    vm.assume(currentlyVested != 0);

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    // Mock some bonded balance
    vm.mockCall(
      currentPool.staking.linearMine,
      abi.encodeWithSelector(RewardMineBase.totalBonded.selector),
      abi.encode(1) // the exact value doesn't matter. It just needs to be non-zero
    );
    vm.mockCall(
      currentPool.rewardSystem.vestingDistributor,
      abi.encodeWithSelector(VestingDistributor.getCurrentlyVested.selector),
      abi.encode(currentlyVested)
    );
    vm.mockCall(
      currentPool.rewardSystem.vestingDistributor,
      abi.encodeWithSelector(VestingDistributor.bondedValue.selector),
      abi.encode(vestingBondedValue)
    );
    vm.mockCall(
      currentPool.staking.linearMine,
      abi.encodeWithSelector(RewardMineBase.valueOfBonded.selector),
      abi.encode(linearBondedValue)
    );

    LinearDistributor linearDistributor = LinearDistributor(
      currentPool.rewardSystem.linearDistributor
    );

    // Set the buffer time to something very long so we dont forfeit any rewards
    vm.prank(admin);
    linearDistributor.setBufferTime(100000 days);

    assertEq(linearDistributor.totalDeclaredReward(), 0);

    vm.prank(randomUser);
    vm.expectRevert("Only rewarder role");
    linearDistributor.declareReward(rewarded);

    vm.startPrank(currentPool.rewardSystem.rewardThrottle);

    // Try declaring 0 reward
    vm.expectRevert("Cannot declare 0 reward");
    linearDistributor.declareReward(0);

    // Declare reward without actually sending the capital
    vm.expectRevert("Insufficient balance");
    linearDistributor.declareReward(rewarded);

    mintRewardToken(address(linearDistributor), rewarded);
    linearDistributor.declareReward(rewarded);

    vm.stopPrank();

    uint256 distributed = (linearBondedValue * currentlyVested) /
      vestingBondedValue;

    // Total declared is always the amount actual sent
    // Due to the setup of this test there is always a surplus, so the actual amount
    // sent to the linear mine is less than actual awarded amount
    assertTrue(distributed < rewarded);
    assertEq(linearDistributor.totalDeclaredReward(), rewarded);
    assertEq(
      rewardToken.balanceOf(currentPool.staking.linearMine),
      distributed
    );
    assertEq(
      RewardMineBase(currentPool.staking.linearMine).totalReleasedReward(),
      distributed
    );
  }

  function testDeclaringSurplusRewardsWithPossibleForfeit(
    address randomUser,
    uint64 rewarded,
    uint64 bondedValue,
    uint256 vestedDiffBps
  ) public {
    assumeNoMaltContracts(randomUser);
    vm.assume(rewarded != 0);
    vm.assume(bondedValue != 0);
    vestedDiffBps = bound(vestedDiffBps, 1, 5000);

    // Make the two mines have the same bonded value
    uint256 vestingBondedValue = bondedValue;
    uint256 linearBondedValue = bondedValue;
    // Amount vested is always less than amount rewarded to the linear distributor
    // This means we always have a surplus on rewards and therefore should retain some
    // behind in the contract
    uint256 currentlyVested = (rewarded * vestedDiffBps) / 10000;
    vm.assume(currentlyVested != 0);

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    // Mock some bonded balance
    vm.mockCall(
      currentPool.staking.linearMine,
      abi.encodeWithSelector(RewardMineBase.totalBonded.selector),
      abi.encode(1) // the exact value doesn't matter. It just needs to be non-zero
    );
    vm.mockCall(
      currentPool.rewardSystem.vestingDistributor,
      abi.encodeWithSelector(VestingDistributor.getCurrentlyVested.selector),
      abi.encode(currentlyVested)
    );
    vm.mockCall(
      currentPool.rewardSystem.vestingDistributor,
      abi.encodeWithSelector(VestingDistributor.bondedValue.selector),
      abi.encode(vestingBondedValue)
    );
    vm.mockCall(
      currentPool.staking.linearMine,
      abi.encodeWithSelector(RewardMineBase.valueOfBonded.selector),
      abi.encode(linearBondedValue)
    );

    LinearDistributor linearDistributor = LinearDistributor(
      currentPool.rewardSystem.linearDistributor
    );

    // Move time forward beyond the `bufferTime` in the linearDistributor
    // This ensures bufferRequirement == distributed which allows us to control forfeits
    vm.warp(block.timestamp + 2 days);

    assertEq(linearDistributor.totalDeclaredReward(), 0);

    vm.prank(randomUser);
    vm.expectRevert("Only rewarder role");
    linearDistributor.declareReward(rewarded);

    vm.startPrank(currentPool.rewardSystem.rewardThrottle);

    // Try declaring 0 reward
    vm.expectRevert("Cannot declare 0 reward");
    linearDistributor.declareReward(0);

    // Declare reward without actually sending the capital
    vm.expectRevert("Insufficient balance");
    linearDistributor.declareReward(rewarded);

    mintRewardToken(address(linearDistributor), rewarded);
    linearDistributor.declareReward(rewarded);

    vm.stopPrank();

    uint256 distributed = (linearBondedValue * currentlyVested) /
      vestingBondedValue;

    // `distributed` amount is sent to linear mine and a further `distributed`
    // is held back for buffer. The remainder is then forfeited
    uint256 distributedOrWitheld = distributed * 2;
    uint256 forfeited;
    if (rewarded > distributedOrWitheld) {
      forfeited = rewarded - distributedOrWitheld;
    }

    // Total declared is always the amount actual sent
    // Due to the setup of this test there is always a surplus, so the actual amount
    // sent to the linear mine is less than actual awarded amount
    assertTrue(distributed < rewarded);
    assertEq(linearDistributor.totalDeclaredReward(), rewarded - forfeited);
    assertEq(
      rewardToken.balanceOf(currentPool.staking.linearMine),
      distributed
    );
    assertEq(
      RewardMineBase(currentPool.staking.linearMine).totalReleasedReward(),
      distributed
    );
  }

  function testBondedValue(uint256 bondedValue) public {
    StabilizedPool memory currentPool = getCurrentStabilizedPool();
    LinearDistributor linearDistributor = LinearDistributor(
      currentPool.rewardSystem.linearDistributor
    );

    vm.mockCall(
      currentPool.staking.linearMine,
      abi.encodeWithSelector(RewardMineBase.valueOfBonded.selector),
      abi.encode(bondedValue)
    );

    assertEq(linearDistributor.bondedValue(), bondedValue);
  }

  function testSetBufferTime(address randomUser, uint256 bufferTime) public {
    assumeNoMaltContracts(randomUser);
    vm.assume(bufferTime != 24 hours);
    StabilizedPool memory currentPool = getCurrentStabilizedPool();
    LinearDistributor linearDistributor = LinearDistributor(
      currentPool.rewardSystem.linearDistributor
    );

    assertEq(linearDistributor.bufferTime(), 24 hours);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin privs");
    linearDistributor.setBufferTime(bufferTime);

    vm.prank(admin);
    linearDistributor.setBufferTime(bufferTime);

    assertEq(linearDistributor.bufferTime(), bufferTime);
  }

  function testSetVestingDistributor(address randomUser, address newAddress)
    public
  {
    assumeNoMaltContracts(randomUser);
    assumeNoMaltContracts(newAddress);
    vm.assume(newAddress != address(0));
    StabilizedPool memory currentPool = getCurrentStabilizedPool();
    LinearDistributor linearDistributor = LinearDistributor(
      currentPool.rewardSystem.linearDistributor
    );

    assertEq(
      address(linearDistributor.vestingDistributor()),
      currentPool.rewardSystem.vestingDistributor
    );

    vm.prank(randomUser);
    vm.expectRevert("Must have admin privs");
    linearDistributor.setVestingDistributor(newAddress);

    vm.prank(admin);
    linearDistributor.setVestingDistributor(newAddress);

    assertEq(address(linearDistributor.vestingDistributor()), newAddress);
  }

  function testSetRewardMine(address randomUser, address newAddress) public {
    assumeNoMaltContracts(randomUser);
    assumeNoMaltContracts(newAddress);
    vm.assume(newAddress != address(0));
    StabilizedPool memory currentPool = getCurrentStabilizedPool();
    LinearDistributor linearDistributor = LinearDistributor(
      currentPool.rewardSystem.linearDistributor
    );

    assertEq(
      address(linearDistributor.rewardMine()),
      currentPool.staking.linearMine
    );
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.REWARD_MINE_ROLE(),
        currentPool.staking.linearMine
      ),
      true
    );
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.REWARD_MINE_ROLE(),
        newAddress
      ),
      false
    );

    vm.prank(randomUser);
    vm.expectRevert("Must have admin privs");
    linearDistributor.setRewardMine(newAddress);

    vm.prank(admin);
    linearDistributor.setRewardMine(newAddress);

    assertEq(address(linearDistributor.rewardMine()), newAddress);
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.REWARD_MINE_ROLE(),
        currentPool.staking.linearMine
      ),
      false
    );
    assertEq(
      linearDistributor.hasRole(
        linearDistributor.REWARD_MINE_ROLE(),
        newAddress
      ),
      true
    );
  }
}
