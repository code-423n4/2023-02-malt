// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./DeployedStabilizedPool.sol";
import "../../contracts/RewardSystem/RewardThrottle.sol";

contract RewardThrottleTest is DeployedStabilizedPool {
  using stdStorage for StdStorage;

  RewardThrottle rewardThrottle;
  StabilizedPool currentPool;

  function setUp() public {
    currentPool = getCurrentStabilizedPool();
    rewardThrottle = RewardThrottle(currentPool.rewardSystem.rewardThrottle);
  }

  function testInitialConditions() public {
    assertEq(address(rewardThrottle.timekeeper()), address(timekeeper));
    assertEq(rewardThrottle.smoothingPeriod(), 24);
    assertEq(rewardThrottle.activeEpoch(), 0);
  }

  function testInitialSetup(address randomUser) public {
    assumeNoMaltContracts(randomUser);

    RewardThrottle newRewardThrottle = new RewardThrottle(
      timelock,
      address(repository),
      address(poolFactory),
      address(timekeeper)
    );

    vm.prank(randomUser);
    vm.expectRevert("Only pool factory role");
    newRewardThrottle.setupContracts(
      currentPool.collateralToken,
      currentPool.rewardSystem.rewardOverflow,
      currentPool.staking.bonding,
      pool
    );

    assertEq(address(newRewardThrottle.collateralToken()), address(0));
    assertEq(address(newRewardThrottle.overflowPool()), address(0));
    assertEq(address(newRewardThrottle.bonding()), address(0));
    assertEq(
      newRewardThrottle.hasRole(
        rewardThrottle.POOL_UPDATER_ROLE(),
        currentPool.updater
      ),
      false
    );

    vm.prank(address(poolFactory));
    newRewardThrottle.setupContracts(
      currentPool.collateralToken,
      currentPool.rewardSystem.rewardOverflow,
      currentPool.staking.bonding,
      pool
    );

    assertEq(
      address(newRewardThrottle.collateralToken()),
      currentPool.collateralToken
    );
    assertEq(
      address(newRewardThrottle.overflowPool()),
      currentPool.rewardSystem.rewardOverflow
    );
    assertEq(address(newRewardThrottle.bonding()), currentPool.staking.bonding);
    assertEq(
      newRewardThrottle.hasRole(
        rewardThrottle.POOL_UPDATER_ROLE(),
        currentPool.updater
      ),
      true
    );
  }

  function testHandleReward(address randomUser, uint256 amount) public {
    vm.assume(amount != 0);
    // 13 ether is < 10% APR given the 600k of liquidity added in the DeployedStabilizedPool setup
    // ether is used as it is also 18 decimal
    amount = bound(amount, 1, 13 ether);

    mintRewardToken(address(rewardThrottle), amount);
    vm.prank(randomUser);
    rewardThrottle.handleReward();

    State memory epochState = rewardThrottle.epochState(0);

    assertEq(epochState.profit, amount);
    // all profit should be rewarded as we we haven't reached the APR requirement
    assertEq(epochState.rewarded, epochState.profit);

    uint256 overflow = rewardToken.balanceOf(
      currentPool.rewardSystem.rewardOverflow
    );
    assertEq(overflow, 0);

    uint256 rewarded = rewardToken.balanceOf(
      currentPool.rewardSystem.vestingDistributor
    );
    assertEq(rewarded, epochState.rewarded);

    VestingDistributor vestingDistributor = VestingDistributor(
      currentPool.rewardSystem.vestingDistributor
    );

    uint256 declaredReward = vestingDistributor.totalDeclaredReward();

    assertEq(declaredReward, epochState.rewarded);

    uint256 epochAPR = rewardThrottle.epochAPR(0);
    // Less than the 10% cap
    assertLt(epochAPR, 1000);

    uint256 epochCashflowAPR = rewardThrottle.epochCashflowAPR(0);
    // We produced less profit than required so cashflow APR is less than 10%
    assertLt(epochCashflowAPR, 1000);

    uint256 epochCashflow = rewardThrottle.epochCashflow(0);
    assertEq(epochCashflow, amount);

    epochState = rewardThrottle.epochState(0);
    State memory nextEpochState = rewardThrottle.epochState(1);

    assertEq(epochState.desiredAPR, 1000);
    assertEq(epochState.epochsPerYear, 4383);

    assertEq(epochState.cumulativeCashflowApr, 0);
    assertEq(nextEpochState.cumulativeCashflowApr, epochCashflowAPR);

    assertEq(epochState.cumulativeApr, 0);
    assertEq(nextEpochState.cumulativeApr, epochAPR);
  }

  function testHandleRewardLargerThanRequired(
    address randomUser,
    uint256 amount
  ) public {
    vm.assume(amount != 0);
    // 14 ether is > 10% APR given the 600k of liquidity added in the DeployedStabilizedPool setup
    // ether is used as it is also 18 decimal
    amount = bound(amount, 14 ether, 10**30);

    mintRewardToken(address(rewardThrottle), amount);
    vm.prank(randomUser);
    rewardThrottle.handleReward();

    State memory epochState = rewardThrottle.epochState(0);

    assertEq(epochState.profit, amount);
    // rewarded should be less than profit as we exceeded
    assertLt(epochState.rewarded, epochState.profit);

    uint256 diff = epochState.profit - epochState.rewarded;
    uint256 overflow = rewardToken.balanceOf(
      currentPool.rewardSystem.rewardOverflow
    );
    assertEq(diff, overflow);

    uint256 rewarded = rewardToken.balanceOf(
      currentPool.rewardSystem.vestingDistributor
    );
    assertEq(rewarded, epochState.rewarded);

    VestingDistributor vestingDistributor = VestingDistributor(
      currentPool.rewardSystem.vestingDistributor
    );

    uint256 declaredReward = vestingDistributor.totalDeclaredReward();

    assertEq(declaredReward, epochState.rewarded);

    uint256 epochAPR = rewardThrottle.epochAPR(0);
    // 10% cap
    assertEq(epochAPR, 999);

    uint256 epochCashflowAPR = rewardThrottle.epochCashflowAPR(0);
    // We produced more profit than required so cashflow APR is higher than 10%
    assertGt(epochCashflowAPR, 1000);

    uint256 epochCashflow = rewardThrottle.epochCashflow(0);
    assertEq(epochCashflow, amount);

    epochState = rewardThrottle.epochState(0);
    State memory nextEpochState = rewardThrottle.epochState(1);

    assertEq(epochState.desiredAPR, 1000);
    assertEq(epochState.epochsPerYear, 4383);

    assertEq(epochState.cumulativeCashflowApr, 0);
    assertEq(nextEpochState.cumulativeCashflowApr, epochCashflowAPR);

    assertEq(epochState.cumulativeApr, 0);
    assertEq(nextEpochState.cumulativeApr, epochAPR);
  }

  function testHandleRewardWithUnderflow(address randomUser, uint256 amount)
    public
  {
    vm.assume(amount != 0);
    // 13 ether is < 10% APR given the 600k of liquidity added in the DeployedStabilizedPool setup
    // ether is used as it is also 18 decimal
    amount = bound(amount, 1, 13 ether);

    uint256 targetProfit = rewardThrottle.targetEpochProfit();

    // Mint more than 1 epoch of rewards into overflow so there is enough to pull from
    uint256 overflowBalance = 200 ether;
    mintRewardToken(currentPool.rewardSystem.rewardOverflow, overflowBalance);

    mintRewardToken(address(rewardThrottle), amount);
    vm.prank(randomUser);
    rewardThrottle.handleReward();

    State memory epochState = rewardThrottle.epochState(0);

    assertEq(epochState.profit, amount);
    assertGt(targetProfit, epochState.profit);
    // all profit should be rewarded as we we haven't reached the APR requirement
    assertEq(epochState.rewarded, epochState.profit);

    // fast forward and fill in the underflow
    vm.warp(block.timestamp + 4 hours);
    timekeeper.advance();
    rewardThrottle.checkRewardUnderflow();

    epochState = rewardThrottle.epochState(0);

    // Profit shouldn't have changed
    assertEq(epochState.profit, amount);
    // But rewarded should be the target amount
    assertEq(epochState.rewarded, targetProfit);
    assertGt(targetProfit, epochState.profit);

    // Capital was pulled from the overflow pool
    uint256 overflow = rewardToken.balanceOf(
      currentPool.rewardSystem.rewardOverflow
    );
    assertEq(overflow, overflowBalance - (targetProfit - epochState.profit));

    VestingDistributor vestingDistributor = VestingDistributor(
      currentPool.rewardSystem.vestingDistributor
    );

    uint256 declaredReward = vestingDistributor.totalDeclaredReward();
    assertEq(declaredReward, targetProfit);

    uint256 epochAPR = rewardThrottle.epochAPR(0);
    // Less than the 10% cap
    assertLt(epochAPR, 1000);

    uint256 epochCashflowAPR = rewardThrottle.epochCashflowAPR(0);
    // We produced less profit than required so cashflow APR is less than 10%
    assertEq(epochCashflowAPR, 999);

    uint256 epochCashflow = rewardThrottle.epochCashflow(0);
    assertEq(epochCashflow, targetProfit);

    epochState = rewardThrottle.epochState(0);
    State memory nextEpochState = rewardThrottle.epochState(1);

    assertEq(epochState.desiredAPR, 1000);
    assertEq(epochState.epochsPerYear, 4383);

    assertEq(epochState.cumulativeCashflowApr, 0);
    assertEq(nextEpochState.cumulativeCashflowApr, epochCashflowAPR);

    assertEq(epochState.cumulativeApr, 0);
    assertEq(nextEpochState.cumulativeApr, epochAPR);
  }

  function testUpdatingDesiredAPRDoesNothingWhenTooEarly() public {
    uint256 lastUpdated = rewardThrottle.aprLastUpdated();

    rewardThrottle.updateDesiredAPR();

    assertEq(rewardThrottle.aprLastUpdated(), lastUpdated);
  }

  function testUpdatingDesiredAPRWhenZeroDeficit() public {
    uint256 lastUpdated = rewardThrottle.aprLastUpdated();
    uint256 updatePeriod = rewardThrottle.aprUpdatePeriod();
    uint256 lastAprTarget = rewardThrottle.targetAPR();

    // Greater than 0
    assertGt(rewardThrottle.runwayDeficit(), 0);

    // Mint a ton of capital into the overflow so runway deficit is 0
    mintRewardToken(currentPool.rewardSystem.rewardOverflow, 100000 ether);

    assertEq(rewardThrottle.runwayDeficit(), 0);

    vm.warp(block.timestamp + updatePeriod);
    rewardThrottle.updateDesiredAPR();

    assertGt(rewardThrottle.aprLastUpdated(), lastUpdated);
    assertEq(rewardThrottle.targetAPR(), lastAprTarget);
  }

  function testUpdatingDesiredAPRWhenAtTargetAPR(uint64 currentEpoch) public {
    uint256 lastUpdated = rewardThrottle.aprLastUpdated();
    uint256 initialTargetAPR = rewardThrottle.targetAPR();
    uint256 smoothingPeriod = rewardThrottle.smoothingPeriod();
    uint256 updatePeriod = rewardThrottle.aprUpdatePeriod();
    uint256 cushionBps = rewardThrottle.cushionBps();
    uint256 adjustmentCap = rewardThrottle.maxAdjustment();
    uint256 targetCashflowAPR = (initialTargetAPR * (10000 + cushionBps)) /
      10000;

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        currentEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(
      currentEpoch
    );

    // Force cashflow APR to be larger than target
    _forceCashflowAPR(
      targetCashflowAPR,
      smoothingPeriod,
      599999999999999999998000
    );

    // Move to beyond the update period
    vm.warp(block.timestamp + updatePeriod);
    rewardThrottle.updateDesiredAPR();

    assertEq(rewardThrottle.targetAPR(), initialTargetAPR);
    assertGt(rewardThrottle.aprLastUpdated(), lastUpdated);
  }

  function testAdjustingAprWhenAprSignificantlyAboveTarget(uint64 currentEpoch)
    public
  {
    uint256 lastUpdated = rewardThrottle.aprLastUpdated();
    uint256 initialTargetAPR = rewardThrottle.targetAPR();
    uint256 smoothingPeriod = rewardThrottle.smoothingPeriod();
    uint256 updatePeriod = rewardThrottle.aprUpdatePeriod();
    uint256 cushionBps = rewardThrottle.cushionBps();
    uint256 adjustmentCap = rewardThrottle.maxAdjustment();
    uint256 targetCashflowAPR = (initialTargetAPR * (10000 + cushionBps)) /
      10000;

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        currentEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(
      currentEpoch
    );

    // Force cashflow APR to be larger than target
    _forceCashflowAPR(
      targetCashflowAPR * 2,
      smoothingPeriod,
      599999999999999999998000
    );

    // Move to beyond the update period
    vm.warp(block.timestamp + updatePeriod);
    rewardThrottle.updateDesiredAPR();

    assertEq(rewardThrottle.targetAPR(), initialTargetAPR + adjustmentCap);
    assertGt(rewardThrottle.aprLastUpdated(), lastUpdated);
  }

  function testAdjustingAprWhenAprSignificantlyBelowTarget(uint64 currentEpoch)
    public
  {
    uint256 lastUpdated = rewardThrottle.aprLastUpdated();
    uint256 initialTargetAPR = rewardThrottle.targetAPR();
    uint256 smoothingPeriod = rewardThrottle.smoothingPeriod();
    uint256 updatePeriod = rewardThrottle.aprUpdatePeriod();
    uint256 cushionBps = rewardThrottle.cushionBps();
    uint256 adjustmentCap = rewardThrottle.maxAdjustment();
    uint256 targetCashflowAPR = (initialTargetAPR * (10000 + cushionBps)) /
      10000;

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        currentEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(
      currentEpoch
    );

    // Force cashflow APR to be less than target
    _forceCashflowAPR(
      targetCashflowAPR / 2,
      smoothingPeriod,
      599999999999999999998000
    );

    // Move to beyond the update period
    vm.warp(block.timestamp + updatePeriod);
    rewardThrottle.updateDesiredAPR();

    assertEq(rewardThrottle.targetAPR(), initialTargetAPR - adjustmentCap);
    assertGt(rewardThrottle.aprLastUpdated(), lastUpdated);
  }

  function testAdjustingAprWhenAprAdjustmentGoesAboveCap(uint64 currentEpoch)
    public
  {
    uint256 lastUpdated = rewardThrottle.aprLastUpdated();
    uint256 initialTargetAPR = rewardThrottle.targetAPR();
    uint256 smoothingPeriod = rewardThrottle.smoothingPeriod();
    uint256 updatePeriod = rewardThrottle.aprUpdatePeriod();
    uint256 cushionBps = rewardThrottle.cushionBps();
    uint256 adjustmentCap = rewardThrottle.maxAdjustment();
    uint256 targetCashflowAPR = (initialTargetAPR * (10000 + cushionBps)) /
      10000;

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        currentEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(
      currentEpoch
    );

    // Force cashflow APR to be less than target
    _forceCashflowAPR(
      targetCashflowAPR * 2,
      smoothingPeriod,
      599999999999999999998000
    );

    uint256 aprCap = initialTargetAPR / 2;

    // Move to beyond the update period
    vm.warp(block.timestamp + updatePeriod);
    rewardThrottle.updateDesiredAPR();

    assertEq(rewardThrottle.targetAPR(), initialTargetAPR + adjustmentCap);
    assertGt(rewardThrottle.aprLastUpdated(), lastUpdated);

    vm.prank(admin);
    rewardThrottle.setAprCap(aprCap);

    vm.warp(block.timestamp + updatePeriod);
    rewardThrottle.updateDesiredAPR();

    assertEq(rewardThrottle.targetAPR(), aprCap);
    assertGt(rewardThrottle.aprLastUpdated(), lastUpdated);
  }

  function testAdjustingAprWhenAprSlightlyAboveTarget(
    uint64 currentEpoch,
    uint256 excessBps
  ) public {
    excessBps = bound(excessBps, 500, 10000);
    uint256 lastUpdated = rewardThrottle.aprLastUpdated();
    uint256 initialTargetAPR = rewardThrottle.targetAPR();
    uint256 smoothingPeriod = rewardThrottle.smoothingPeriod();
    uint256 updatePeriod = rewardThrottle.aprUpdatePeriod();
    uint256 cushionBps = rewardThrottle.cushionBps();
    uint256 adjustmentCap = rewardThrottle.maxAdjustment();
    uint256 gain = rewardThrottle.proportionalGainBps();
    uint256 targetCashflowAPR = (initialTargetAPR * (10000 + cushionBps)) /
      10000;
    uint256 excess = (adjustmentCap * excessBps) / 10000;

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        currentEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(
      currentEpoch
    );

    // Force cashflow APR to be larger than target
    _forceCashflowAPR(
      targetCashflowAPR + ((excess * 10000) / gain),
      smoothingPeriod,
      599999999999999999998000
    );

    // Move to beyond the update period
    vm.warp(block.timestamp + updatePeriod);
    rewardThrottle.updateDesiredAPR();

    assertApproxEqAbs(rewardThrottle.targetAPR(), initialTargetAPR + excess, 1);
    assertGt(rewardThrottle.aprLastUpdated(), lastUpdated);
  }

  function testAdjustingAprWhenAprSlightlyBelowTarget(
    uint64 currentEpoch,
    uint256 excessBps
  ) public {
    excessBps = bound(excessBps, 500, 10000);
    uint256 lastUpdated = rewardThrottle.aprLastUpdated();
    uint256 initialTargetAPR = rewardThrottle.targetAPR();
    uint256 smoothingPeriod = rewardThrottle.smoothingPeriod();
    uint256 updatePeriod = rewardThrottle.aprUpdatePeriod();
    uint256 cushionBps = rewardThrottle.cushionBps();
    uint256 adjustmentCap = rewardThrottle.maxAdjustment();
    uint256 gain = rewardThrottle.proportionalGainBps();
    uint256 targetCashflowAPR = (initialTargetAPR * (10000 + cushionBps)) /
      10000;
    uint256 excess = (adjustmentCap * excessBps) / 10000;

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        currentEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(
      currentEpoch
    );

    // Force cashflow APR to be less than target
    _forceCashflowAPR(
      targetCashflowAPR - ((excess * 10000) / gain),
      smoothingPeriod,
      599999999999999999998000
    );

    // Move to beyond the update period
    vm.warp(block.timestamp + updatePeriod);
    rewardThrottle.updateDesiredAPR();

    assertApproxEqAbs(rewardThrottle.targetAPR(), initialTargetAPR - excess, 1);
    assertGt(rewardThrottle.aprLastUpdated(), lastUpdated);
  }

  function testRunwayReturnedCorrectly(uint256 epochs) public {
    epochs = bound(epochs, 1, 20000);
    uint256 targetProfit = rewardThrottle.targetEpochProfit();
    uint256 epochsPerDay = 86400 / timekeeper.epochLength();
    uint256 overflowBalance = epochs * targetProfit;
    mintRewardToken(currentPool.rewardSystem.rewardOverflow, overflowBalance);

    (uint256 runwayEpochs, uint256 runwayDays) = rewardThrottle.runway();

    assertEq(runwayEpochs, epochs);
    assertEq(runwayDays, runwayEpochs / epochsPerDay);

    uint256 desiredRunway = rewardThrottle.desiredRunway();
    uint256 desiredEpochs = (timekeeper.epochsPerYear() * desiredRunway) /
      31557600;
    uint256 desiredProfit = targetProfit * desiredEpochs;

    uint256 deficit = rewardThrottle.runwayDeficit();

    uint256 expectedDeficit;

    if (desiredProfit > overflowBalance) {
      expectedDeficit = desiredProfit - overflowBalance;
    }

    assertEq(deficit, expectedDeficit);
  }

  function testAverageAPR(
    uint256 period,
    uint256 endEpoch,
    uint256 forcedAPR
  ) public {
    forcedAPR = bound(forcedAPR, 50, 500000);
    period = bound(period, 1, 50);
    uint256 startEpoch;

    if (endEpoch > period) {
      startEpoch = endEpoch - period;
    }

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        endEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(endEpoch);

    _forceAPR(forcedAPR, period, 599999999999999999998000);

    uint256 apr = rewardThrottle.averageAPR(startEpoch, endEpoch);

    assertApproxEqAbs(apr, forcedAPR, 1);
  }

  function testAverageCashflowAPR(
    uint256 period,
    uint256 endEpoch,
    uint256 forcedAPR
  ) public {
    forcedAPR = bound(forcedAPR, 50, 500000);
    period = bound(period, 1, 50);
    uint256 startEpoch;

    if (endEpoch > period) {
      startEpoch = endEpoch - period;
    }

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        endEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(endEpoch);

    _forceCashflowAPR(forcedAPR, period, 599999999999999999998000);

    uint256 apr = rewardThrottle.averageCashflowAPR(startEpoch, endEpoch);

    assertApproxEqAbs(apr, forcedAPR, 1);
  }

  function testAverageCashflowAPRTwo(
    uint256 period,
    uint256 endEpoch,
    uint256 forcedAPR
  ) public {
    forcedAPR = bound(forcedAPR, 50, 500000);
    period = bound(period, 1, 50);
    uint256 startEpoch;

    if (endEpoch > period) {
      startEpoch = endEpoch - period;
    }

    stdstore.target(address(rewardThrottle)).sig("activeEpoch()").checked_write(
        endEpoch
      );
    stdstore.target(address(timekeeper)).sig("epoch()").checked_write(endEpoch);

    _forceCashflowAPR(forcedAPR, period, 599999999999999999998000);

    uint256 apr = rewardThrottle.averageCashflowAPR(period);

    assertApproxEqAbs(apr, forcedAPR, 1);
  }

  function testFillingInEpochGaps(uint256 epoch, uint256 profit) public {
    profit = bound(profit, 10**18, 10**40);
    epoch = bound(epoch, 1, 72);

    uint256 desiredAPR = rewardThrottle.targetAPR();

    assertEq(rewardThrottle.activeEpoch(), 0);

    State memory lastEpochState = rewardThrottle.epochState(epoch);

    assertEq(lastEpochState.cumulativeApr, 0);
    assertEq(lastEpochState.cumulativeCashflowApr, 0);
    assertEq(lastEpochState.bondedValue, 0);
    assertEq(lastEpochState.active, false);

    vm.mockCall(
      currentPool.staking.bonding,
      abi.encodeWithSelector(Bonding.averageBondedValue.selector),
      abi.encode(599999999999999999998000)
    );

    mintRewardToken(address(rewardThrottle), profit);
    vm.prank(address(213));
    rewardThrottle.handleReward();

    _fastForwardToEpoch(epoch);

    bytes32 encodedZero = bytes32(abi.encode(0));

    rewardThrottle.fillInEpochGaps();

    State memory firstEpochState = rewardThrottle.epochState(0);

    uint256 apr = rewardThrottle.epochAPR(0);
    uint256 cashflowApr = rewardThrottle.epochCashflowAPR(0);

    // epoch 0 should have 0s in accumulators
    assertEq(firstEpochState.cumulativeApr, 0);
    assertEq(firstEpochState.cumulativeCashflowApr, 0);
    assertEq(firstEpochState.bondedValue, 599999999999999999998000);
    assertEq(firstEpochState.desiredAPR, desiredAPR);

    lastEpochState = rewardThrottle.epochState(epoch);

    // Final accumulators should have picked up the APR from epoch 0
    assertEq(lastEpochState.cumulativeApr, apr);
    assertEq(lastEpochState.cumulativeCashflowApr, cashflowApr);
    assertEq(lastEpochState.bondedValue, 599999999999999999998000);
    assertEq(lastEpochState.desiredAPR, desiredAPR);
    assertEq(lastEpochState.active, true);

    assertEq(rewardThrottle.activeEpoch(), epoch);
  }

  function testCheckingRewardUnderflow(uint256 epoch, uint256 profit) public {
    profit = bound(profit, 10**18, 10**40);
    epoch = bound(epoch, 1, 72);

    uint256 desiredAPR = rewardThrottle.targetAPR();

    assertEq(rewardThrottle.activeEpoch(), 0);

    State memory lastEpochState = rewardThrottle.epochState(epoch);

    assertEq(lastEpochState.cumulativeApr, 0);
    assertEq(lastEpochState.cumulativeCashflowApr, 0);
    assertEq(lastEpochState.bondedValue, 0);
    assertEq(lastEpochState.active, false);

    vm.mockCall(
      currentPool.staking.bonding,
      abi.encodeWithSelector(Bonding.averageBondedValue.selector),
      abi.encode(599999999999999999998000)
    );

    mintRewardToken(address(rewardThrottle), profit);
    vm.prank(address(213));
    rewardThrottle.handleReward();

    _fastForwardToEpoch(epoch);

    // Add tons of capital to overflow to fullfil the underflows
    uint256 overflowBalance = 200000000 ether;
    mintRewardToken(currentPool.rewardSystem.rewardOverflow, overflowBalance);

    assertEq(
      rewardToken.balanceOf(currentPool.rewardSystem.rewardOverflow),
      overflowBalance
    );

    rewardThrottle.checkRewardUnderflow();

    uint256 apr = rewardThrottle.averageAPR(0, epoch);

    assertApproxEqAbs(apr, desiredAPR, 1);

    uint256 targetProfit = rewardThrottle.targetEpochProfit();
    uint256 initiallyRewarded = profit;

    if (profit > targetProfit) {
      initiallyRewarded = targetProfit;
    }

    uint256 finalOverflowBalance = rewardToken.balanceOf(
      currentPool.rewardSystem.rewardOverflow
    );

    // `profit` was already made so didn't need to come from overflow
    uint256 distributedProfit = (targetProfit * epoch) - initiallyRewarded;
    uint256 expectedOverflow = overflowBalance - distributedProfit;

    // Check that capital was pulled from the overflow pool
    assertEq(finalOverflowBalance, expectedOverflow);

    VestingDistributor vestingDistributor = VestingDistributor(
      currentPool.rewardSystem.vestingDistributor
    );

    uint256 declaredReward = vestingDistributor.totalDeclaredReward();

    // Check that the rewards were sent to the vesting distributor contract
    assertEq(declaredReward, distributedProfit + initiallyRewarded);
  }

  // populateFromPreviousThrottle
  // handleReward with multiple active mines
  // all the admin set methods

  function _fastForwardToEpoch(uint256 epoch) internal {
    uint256 epochLength = timekeeper.epochLength();
    uint256 currentEpoch = timekeeper.epoch();

    for (uint256 i = currentEpoch; i < epoch; ++i) {
      vm.warp(block.timestamp + epochLength + 1);
      timekeeper.advance();
    }
  }

  function _forceAPR(
    uint256 apr,
    uint256 smoothingPeriod,
    uint256 bondedValue
  ) internal {
    // helper to force cashflow APR to a certain value
    uint256 endEpoch = rewardThrottle.activeEpoch();
    uint256 epochsPerYear = timekeeper.epochsPerYear();
    uint256 startEpoch;

    if (endEpoch < smoothingPeriod) {
      smoothingPeriod = endEpoch;
    } else {
      startEpoch = endEpoch - smoothingPeriod;
    }

    uint256 rewarded = ((bondedValue * apr) / 10000) / epochsPerYear;

    stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(endEpoch)
      .depth(1)
      .checked_write(rewarded); // rewarded
    stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(endEpoch)
      .depth(2)
      .checked_write(bondedValue); // bondedValue
    stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(endEpoch)
      .depth(3)
      .checked_write(epochsPerYear); // epochsPerYear

    vm.mockCall(
      currentPool.staking.bonding,
      abi.encodeWithSelector(Bonding.averageBondedValue.selector, endEpoch),
      abi.encode(bondedValue)
    );

    // Update startEpoch
    uint256 slot = stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(startEpoch)
      .depth(6)
      .find(); // cumulativeApr
    bytes32 loc = bytes32(slot);
    bytes32 mockedBalance = bytes32(abi.encode(0));
    vm.store(address(rewardThrottle), loc, mockedBalance);

    uint256 cumulativeApr = apr * smoothingPeriod;
    // Update cumulativeApr on endEpoch
    stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(endEpoch)
      .depth(6)
      .checked_write(cumulativeApr); // cumulativeApr

    if (endEpoch > 0) {
      // Update cumulativeApr on second to last epoch
      // This is used as the baseline when refreshing the current
      // epoch in parts of the code
      stdstore
        .target(address(rewardThrottle))
        .sig("state(uint256)")
        .with_key(endEpoch - 1)
        .depth(6)
        .checked_write(cumulativeApr - apr); // cumulativeApr
      stdstore
        .target(address(rewardThrottle))
        .sig("state(uint256)")
        .with_key(endEpoch - 1)
        .depth(1)
        .checked_write(rewarded); // rewarded
      stdstore
        .target(address(rewardThrottle))
        .sig("state(uint256)")
        .with_key(endEpoch - 1)
        .depth(2)
        .checked_write(bondedValue); // bondedValue
      stdstore
        .target(address(rewardThrottle))
        .sig("state(uint256)")
        .with_key(endEpoch - 1)
        .depth(3)
        .checked_write(epochsPerYear); // epochsPerYear

      vm.mockCall(
        currentPool.staking.bonding,
        abi.encodeWithSelector(
          Bonding.averageBondedValue.selector,
          endEpoch - 1
        ),
        abi.encode(bondedValue)
      );
    }
  }

  function _forceCashflowAPR(
    uint256 apr,
    uint256 smoothingPeriod,
    uint256 bondedValue
  ) internal {
    // helper to force cashflow APR to a certain value
    uint256 endEpoch = rewardThrottle.activeEpoch();
    uint256 epochsPerYear = timekeeper.epochsPerYear();
    uint256 startEpoch;

    if (endEpoch < smoothingPeriod) {
      smoothingPeriod = endEpoch;
    } else {
      startEpoch = endEpoch - smoothingPeriod;
    }

    uint256 profit = ((bondedValue * apr) / 10000) / epochsPerYear;

    stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(endEpoch)
      .depth(0)
      .checked_write(profit); // profit
    stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(endEpoch)
      .depth(2)
      .checked_write(bondedValue); // bondedValue
    stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(endEpoch)
      .depth(3)
      .checked_write(epochsPerYear); // epochsPerYear

    vm.mockCall(
      currentPool.staking.bonding,
      abi.encodeWithSelector(Bonding.averageBondedValue.selector, endEpoch),
      abi.encode(bondedValue)
    );

    // Update startEpoch
    uint256 slot = stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(startEpoch)
      .depth(5)
      .find(); // cumulativeCashflowApr
    bytes32 loc = bytes32(slot);
    bytes32 mockedBalance = bytes32(abi.encode(0));
    vm.store(address(rewardThrottle), loc, mockedBalance);

    uint256 cumulativeCashflowApr = apr * smoothingPeriod;
    // Update cumulativeCashflowApr on endEpoch
    stdstore
      .target(address(rewardThrottle))
      .sig("state(uint256)")
      .with_key(endEpoch)
      .depth(5)
      .checked_write(cumulativeCashflowApr); // cumulativeCashflowApr

    if (endEpoch > 0) {
      // Update cumulativeCashflowApr on second to last epoch
      // This is used as the baseline when refreshing the current
      // epoch in parts of the code
      stdstore
        .target(address(rewardThrottle))
        .sig("state(uint256)")
        .with_key(endEpoch - 1)
        .depth(5)
        .checked_write(cumulativeCashflowApr - apr); // cumulativeCashflowApr
      stdstore
        .target(address(rewardThrottle))
        .sig("state(uint256)")
        .with_key(endEpoch - 1)
        .depth(0)
        .checked_write(profit); // profit
      stdstore
        .target(address(rewardThrottle))
        .sig("state(uint256)")
        .with_key(endEpoch - 1)
        .depth(2)
        .checked_write(bondedValue); // bondedValue
      stdstore
        .target(address(rewardThrottle))
        .sig("state(uint256)")
        .with_key(endEpoch - 1)
        .depth(3)
        .checked_write(epochsPerYear); // epochsPerYear

      vm.mockCall(
        currentPool.staking.bonding,
        abi.encodeWithSelector(
          Bonding.averageBondedValue.selector,
          endEpoch - 1
        ),
        abi.encode(bondedValue)
      );
    }
  }
}
