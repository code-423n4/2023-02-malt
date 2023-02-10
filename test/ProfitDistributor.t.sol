// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "../../contracts/StabilityPod/ProfitDistributor.sol";
import "../../contracts/GlobalImpliedCollateralService.sol";
import "../../contracts/RewardSystem/RewardThrottle.sol";
import "../../contracts/StabilityPod/LiquidityExtension.sol";
import "../../contracts/StabilityPod/ImpliedCollateralService.sol";
import "../../contracts/Auction/Auction.sol";
import "../../contracts/DataFeed/MaltDataLab.sol";

contract ProfitDistributorTest is MaltTest {
  using stdStorage for StdStorage;

  ProfitDistributor profitDistributor;

  address dao = nextAddress();
  address swingTrader = nextAddress();
  address liquidityExtension = nextAddress();
  address impliedCollateralService = nextAddress();
  address auction = nextAddress();
  address rewardThrottle = nextAddress();
  address globalIC = nextAddress();
  address lpToken = nextAddress();
  address maltDataLab = nextAddress();
  address poolFactory = nextAddress();
  address updater = nextAddress();

  function setUp() public {
    profitDistributor = new ProfitDistributor(
      timelock,
      address(repository),
      poolFactory,
      dao,
      treasury
    );

    vm.prank(poolFactory);
    vm.mockCall(
      poolFactory,
      abi.encodeWithSelector(IStabilizedPoolFactory.getPool.selector, lpToken),
      abi.encode(address(0), updater, "")
    );
    profitDistributor.setupContracts(
      address(malt),
      address(rewardToken),
      globalIC,
      rewardThrottle,
      swingTrader,
      liquidityExtension,
      auction,
      maltDataLab,
      impliedCollateralService,
      lpToken
    );

    vm.prank(admin);
    address[] memory admins = new address[](1);
    admins[0] = admin;
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

  function testSendsAllRewardsToLpWhenNoSwingTraderDeficit(
    uint256 profit,
    uint256 decimals
  ) public {
    decimals = bound(decimals, 3, 50);
    profit = bound(profit, 10000, 2**64); // larger than $1
    rewardToken.setDecimals(decimals);

    uint256 distributionBps = profitDistributor.distributeBps();

    /*
     * MOCKS
     */
    // Mock rewardThrottle.checkRewardUnderflow
    // Returns nothing. Needs to be mocked so it doesn't fail
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.checkRewardUnderflow.selector),
      ""
    );

    // Mock liquidityExtension.collateralDeficit.
    // 0 deficit. Just means rewards pass through to rest of distribution
    vm.mockCall(
      liquidityExtension,
      abi.encodeWithSelector(LiquidityExtension.collateralDeficit.selector),
      abi.encode(0, decimals)
    );

    // mock auction.allocateArbRewards
    // Returns full profit. Meaning 0 allocated to arb. Rewards continue to rest of distribution
    vm.mockCall(
      auction,
      abi.encodeWithSelector(Auction.allocateArbRewards.selector),
      abi.encode(profit)
    );

    // Mock maltDataLab.priceTarget
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.priceTarget.selector),
      abi.encode(10**decimals)
    );

    // Mock globalIC.swingTraderCollateralDeficit
    // Setting this to 0 should mean all distribution rewards go to LPs
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralDeficit.selector
      ),
      abi.encode(0) // because this is 0 all rewards should go to LPs
    );

    // Mock maltDataLab.maltToRewardDecimals
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(MaltDataLab.maltToRewardDecimals.selector, 0),
      abi.encode(0)
    );

    /*
     * Execution
     */
    uint256 swingTraderInitialBalance = rewardToken.balanceOf(swingTrader);
    uint256 throttleInitialBalance = rewardToken.balanceOf(rewardThrottle);
    uint256 treasuryInitialBalance = rewardToken.balanceOf(treasury);
    assertEq(swingTraderInitialBalance, 0);
    assertEq(throttleInitialBalance, 0);
    assertEq(treasuryInitialBalance, 0);
    mintRewardToken(address(profitDistributor), profit);
    profitDistributor.handleProfit(profit);

    /*
     * Assertions
     */
    uint256 swingTraderFinalBalance = rewardToken.balanceOf(swingTrader);
    uint256 throttleFinalBalance = rewardToken.balanceOf(rewardThrottle);
    uint256 treasuryFinalBalance = rewardToken.balanceOf(treasury);
    assertEq(swingTraderFinalBalance, 0);
    assertEq(throttleFinalBalance, (profit * distributionBps) / 10000);
    assertEq(treasuryFinalBalance, profit - throttleFinalBalance);
  }

  function testSendsMaxContributionToLE(
    uint256 profit,
    uint256 decimals,
    uint256 maxContributionBps
  ) public {
    maxContributionBps = bound(maxContributionBps, 100, 10000);
    profit = bound(profit, 10000, 2**64); // larger than $1
    decimals = bound(decimals, 3, 50);
    rewardToken.setDecimals(decimals);
    vm.prank(admin);
    profitDistributor.setMaxLEContribution(maxContributionBps);

    /*
     * MOCKS
     */
    // Mock rewardThrottle.checkRewardUnderflow
    // Returns nothing. Needs to be mocked so it doesn't fail
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.checkRewardUnderflow.selector),
      ""
    );

    // Mock liquidityExtension.collateralDeficit.
    // LE deficit is entire profit this time. So maxContributionBps of rewards should be used to replenish LE
    vm.mockCall(
      liquidityExtension,
      abi.encodeWithSelector(LiquidityExtension.collateralDeficit.selector),
      abi.encode(profit, decimals)
    );

    // mock auction.allocateArbRewards
    // Nothing given to arb. maxContrib is given to LE and all remainder is returned from arb, meaning arb took nothing
    uint256 maxContrib = (profit * maxContributionBps) / 10000;
    vm.mockCall(
      auction,
      abi.encodeWithSelector(Auction.allocateArbRewards.selector),
      abi.encode(profit - maxContrib)
    );

    // Mock maltDataLab.priceTarget
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.priceTarget.selector),
      abi.encode(10**decimals)
    );

    // Mock globalIC.swingTraderCollateralDeficit
    // Swing Trader has no deficit
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralDeficit.selector
      ),
      abi.encode(0)
    );

    // Mock maltDataLab.maltToRewardDecimals
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(MaltDataLab.maltToRewardDecimals.selector, 0),
      abi.encode(0)
    );

    /*
     * Execution
     */
    uint256 liquidityExtensionInitialBalance = rewardToken.balanceOf(
      liquidityExtension
    );
    assertEq(liquidityExtensionInitialBalance, 0);
    mintRewardToken(address(profitDistributor), profit);
    profitDistributor.handleProfit(profit);

    /*
     * Assertions
     */
    uint256 liquidityExtensionFinalBalance = rewardToken.balanceOf(
      liquidityExtension
    );
    assertEq(liquidityExtensionFinalBalance, maxContrib);
    // LPs should have got the rest
    uint256 distributionBps = profitDistributor.distributeBps();
    uint256 distributionCut = ((profit - maxContrib) * distributionBps) / 10000;
    uint256 rewardThrottleFinalBalance = rewardToken.balanceOf(rewardThrottle);
    assertEq(rewardThrottleFinalBalance, distributionCut);
  }

  function testSendsDeficitToLE(
    uint256 profit,
    uint256 decimals,
    uint256 maxContributionBps,
    uint256 distributeBps
  ) public {
    maxContributionBps = bound(maxContributionBps, 100, 10000);
    distributeBps = bound(distributeBps, 100, 10000);
    profit = bound(profit, 10000, 2**64); // larger than $1
    decimals = bound(decimals, 3, 50);
    rewardToken.setDecimals(decimals);
    vm.prank(admin);
    profitDistributor.setMaxLEContribution(maxContributionBps);
    vm.prank(admin);
    profitDistributor.setDistributeBps(distributeBps);

    /*
     * MOCKS
     */
    // Mock rewardThrottle.checkRewardUnderflow
    // Returns nothing. Needs to be mocked so it doesn't fail
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.checkRewardUnderflow.selector),
      ""
    );

    // Mock liquidityExtension.collateralDeficit.
    // Ensure deficit is smaller than the maxContributionBps amount of profit
    // This way the entire deficit should be used
    uint256 deficit = (profit * maxContributionBps) / 10000 / 2;
    vm.mockCall(
      liquidityExtension,
      abi.encodeWithSelector(LiquidityExtension.collateralDeficit.selector),
      abi.encode(deficit, decimals)
    );

    // mock auction.allocateArbRewards
    // Nothing given to arb. deficit is given to LE and all remainder is returned from arb, meaning arb took nothing
    vm.mockCall(
      auction,
      abi.encodeWithSelector(Auction.allocateArbRewards.selector),
      abi.encode(profit - deficit)
    );

    // Mock maltDataLab.priceTarget
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.priceTarget.selector),
      abi.encode(10**decimals)
    );

    // Mock globalIC.swingTraderCollateralDeficit
    // Swing Trader has no deficit
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralDeficit.selector
      ),
      abi.encode(0) // because this is 0 all rewards should go to LPs
    );

    // Mock maltDataLab.maltToRewardDecimals
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(MaltDataLab.maltToRewardDecimals.selector, 0),
      abi.encode(0)
    );

    /*
     * Execution
     */
    uint256 liquidityExtensionInitialBalance = rewardToken.balanceOf(
      liquidityExtension
    );
    assertEq(liquidityExtensionInitialBalance, 0);
    mintRewardToken(address(profitDistributor), profit);
    profitDistributor.handleProfit(profit);

    /*
     * Assertions
     */
    uint256 liquidityExtensionFinalBalance = rewardToken.balanceOf(
      liquidityExtension
    );
    assertEq(liquidityExtensionFinalBalance, deficit);
    // LPs should have got the rest
    uint256 distributionBps = profitDistributor.distributeBps();
    uint256 distributionCut = ((profit - deficit) * distributionBps) / 10000;
    uint256 rewardThrottleFinalBalance = rewardToken.balanceOf(rewardThrottle);
    assertEq(rewardThrottleFinalBalance, distributionCut);
  }

  function testCleanlyExitsWhenArbTokensTakeAllRewards(
    uint256 profit,
    uint256 decimals
  ) public {
    decimals = bound(decimals, 3, 50);
    profit = bound(profit, 10000, 2**64); // larger than $1
    rewardToken.setDecimals(decimals);

    uint256 distributionBps = profitDistributor.distributeBps();

    /*
     * MOCKS
     */
    // Mock rewardThrottle.checkRewardUnderflow
    // Returns nothing. Needs to be mocked so it doesn't fail
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.checkRewardUnderflow.selector),
      ""
    );

    // Mock liquidityExtension.collateralDeficit. 0 deficit
    // LE has 0 deficit, so takes nothing. All rewards continue downstream
    vm.mockCall(
      liquidityExtension,
      abi.encodeWithSelector(LiquidityExtension.collateralDeficit.selector),
      abi.encode(0, decimals)
    );

    // mock auction.allocateArbRewards
    // Returns 0. Meaning all rewards are allocated to arb
    vm.mockCall(
      auction,
      abi.encodeWithSelector(Auction.allocateArbRewards.selector),
      abi.encode(0)
    );

    /*
     * Execution
     */
    mintRewardToken(address(profitDistributor), profit);
    profitDistributor.handleProfit(profit);

    /*
     * Assertions
     */
    uint256 swingTraderFinalBalance = rewardToken.balanceOf(swingTrader);
    uint256 throttleFinalBalance = rewardToken.balanceOf(rewardThrottle);
    uint256 treasuryFinalBalance = rewardToken.balanceOf(treasury);
    assertEq(swingTraderFinalBalance, 0);
    assertEq(throttleFinalBalance, 0);
    assertEq(treasuryFinalBalance, 0);
  }

  function testSendsAllProfitToSwingTraderWhenRunwayIsFull(
    uint256 profit,
    uint256 decimals
  ) public {
    decimals = bound(decimals, 3, 50);
    profit = bound(profit, 10000, 2**64); // larger than $1
    rewardToken.setDecimals(decimals);

    uint256 distributionBps = profitDistributor.distributeBps();

    /*
     * MOCKS
     */
    // Mock rewardThrottle.checkRewardUnderflow
    // Returns nothing. Needs to be mocked so it doesn't fail
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.checkRewardUnderflow.selector),
      ""
    );

    // Mock liquidityExtension.collateralDeficit. 0 deficit
    // LE has 0 deficit, so takes nothing. All rewards continue downstream
    vm.mockCall(
      liquidityExtension,
      abi.encodeWithSelector(LiquidityExtension.collateralDeficit.selector),
      abi.encode(0, decimals)
    );

    // mock auction.allocateArbRewards
    // Returns full profit. Meaning 0 allocated to arb
    vm.mockCall(
      auction,
      abi.encodeWithSelector(Auction.allocateArbRewards.selector),
      abi.encode(profit)
    );

    // Mock maltDataLab.priceTarget
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.priceTarget.selector),
      abi.encode(10**decimals)
    );

    // Mock globalIC.swingTraderCollateralDeficit
    // Deficit is full profit amount on ST. ST should get all rewards
    uint256 stDeficit = rewardToMaltDecimals(profit, decimals);
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralDeficit.selector
      ),
      abi.encode(stDeficit) // deficit is not 0
    );

    // Mock maltDataLab.maltToRewardDecimals
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(
        MaltDataLab.maltToRewardDecimals.selector,
        stDeficit
      ),
      abi.encode(profit)
    );

    // 0 deficit on runway. No rewards should be given here
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.runwayDeficit.selector),
      abi.encode(0) // runway deficit is 0, so all rewards go to swing trader
    );

    /*
     * Execution
     */
    uint256 swingTraderInitialBalance = rewardToken.balanceOf(swingTrader);
    uint256 throttleInitialBalance = rewardToken.balanceOf(rewardThrottle);
    uint256 treasuryInitialBalance = rewardToken.balanceOf(treasury);
    assertEq(swingTraderInitialBalance, 0);
    assertEq(throttleInitialBalance, 0);
    assertEq(treasuryInitialBalance, 0);
    mintRewardToken(address(profitDistributor), profit);
    profitDistributor.handleProfit(profit);

    /*
     * Assertions
     */
    uint256 swingTraderFinalBalance = rewardToken.balanceOf(swingTrader);
    uint256 throttleFinalBalance = rewardToken.balanceOf(rewardThrottle);
    uint256 treasuryFinalBalance = rewardToken.balanceOf(treasury);
    assertEq(swingTraderFinalBalance, (profit * distributionBps) / 10000);
    assertEq(throttleFinalBalance, 0);
    assertEq(treasuryFinalBalance, profit - swingTraderFinalBalance);
  }

  function testSendsAllToSwingTraderWhenPoolRatioIsUnderGlobalRatio(
    uint256 profit,
    uint256 decimals,
    uint256 swingTraderPrefBps
  ) public {
    swingTraderPrefBps = bound(swingTraderPrefBps, 100, 10000);
    decimals = bound(decimals, 3, 50);
    profit = bound(profit, 10000, 2**64); // larger than $1
    rewardToken.setDecimals(decimals);
    vm.prank(admin);
    profitDistributor.setSwingTraderPreferenceBps(swingTraderPrefBps);

    uint256 distributionBps = profitDistributor.distributeBps();

    /*
     * MOCKS
     */
    // Mock rewardThrottle.checkRewardUnderflow
    // Returns nothing. Needs to be mocked so it doesn't fail
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.checkRewardUnderflow.selector),
      ""
    );

    // Mock liquidityExtension.collateralDeficit. 0 deficit
    // LE has 0 deficit, so takes nothing. All rewards continue downstream
    vm.mockCall(
      liquidityExtension,
      abi.encodeWithSelector(LiquidityExtension.collateralDeficit.selector),
      abi.encode(0, decimals)
    );

    // mock auction.allocateArbRewards
    // Returns full profit. Meaning 0 allocated to arb
    vm.mockCall(
      auction,
      abi.encodeWithSelector(Auction.allocateArbRewards.selector),
      abi.encode(profit)
    );

    // Mock maltDataLab.priceTarget
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.priceTarget.selector),
      abi.encode(10**decimals)
    );

    // Mock globalIC.swingTraderCollateralDeficit. Has full deficit
    // Deficit is full profit amount on ST. ST should get all rewards
    uint256 stDeficit = rewardToMaltDecimals(profit, decimals);
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralDeficit.selector
      ),
      abi.encode(stDeficit) // deficit is not 0
    );

    // Mock maltDataLab.maltToRewardDecimals(deficit)
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(
        MaltDataLab.maltToRewardDecimals.selector,
        stDeficit
      ),
      abi.encode(profit)
    );

    // Mock rewardThrottle.runwayDeficit. Has full deficit
    // Deficit for runway is full amount too. The deciding factor of where the capital goes
    // should be in the local and global ST ratios below
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.runwayDeficit.selector),
      abi.encode(profit) // deficit is not 0
    );

    // Mock maltDataLab.maltToRewardDecimals(deficit)
    uint256 ratio = 1000;
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralRatio.selector
      ),
      abi.encode(ratio) // any value above 0 is fine as below local ratio is defined as 0
    );
    // This doesn't matter, as long as output is above 0
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(MaltDataLab.maltToRewardDecimals.selector, ratio),
      abi.encode(ratio)
    );

    vm.mockCall(
      impliedCollateralService,
      abi.encodeWithSelector(
        ImpliedCollateralService.swingTraderCollateralRatio.selector
      ),
      abi.encode(0)
    );

    /*
     * Execution
     */
    mintRewardToken(address(profitDistributor), profit);
    profitDistributor.handleProfit(profit);

    /*
     * Assertions
     */
    uint256 swingTraderFinalBalance = rewardToken.balanceOf(swingTrader);
    uint256 throttleFinalBalance = rewardToken.balanceOf(rewardThrottle);
    uint256 treasuryFinalBalance = rewardToken.balanceOf(treasury);

    uint256 distributionCut = (profit * distributionBps) / 10000;
    uint256 swingTraderCut = (distributionCut *
      profitDistributor.swingTraderPreferenceBps()) / 10000;
    assertEq(swingTraderFinalBalance, swingTraderCut);
    assertEq(throttleFinalBalance, distributionCut - swingTraderCut);
    assertEq(treasuryFinalBalance, profit - distributionCut);
  }

  function testBalancesProfitBetweenSTandLP(
    uint256 profit,
    uint256 decimals,
    uint64 stDeficit,
    uint64 runwayDeficit
  ) public {
    decimals = bound(decimals, 3, 50);
    profit = bound(profit, 10000, 2**64); // larger than $1
    vm.assume(stDeficit != 0);
    vm.assume(runwayDeficit != 0);
    rewardToken.setDecimals(decimals);

    uint256 distributionBps = profitDistributor.distributeBps();

    /*
     * MOCKS
     */
    // Mock rewardThrottle.checkRewardUnderflow
    // Returns nothing. Needs to be mocked so it doesn't fail
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.checkRewardUnderflow.selector),
      ""
    );

    // Mock liquidityExtension.collateralDeficit. 0 deficit
    // LE has 0 deficit, so takes nothing. All rewards continue downstream
    vm.mockCall(
      liquidityExtension,
      abi.encodeWithSelector(LiquidityExtension.collateralDeficit.selector),
      abi.encode(0, decimals)
    );

    // mock auction.allocateArbRewards
    // Returns full profit. Meaning 0 allocated to arb
    vm.mockCall(
      auction,
      abi.encodeWithSelector(Auction.allocateArbRewards.selector),
      abi.encode(profit)
    );

    // Mock maltDataLab.priceTarget
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.priceTarget.selector),
      abi.encode(10**decimals)
    );

    // Mock globalIC.swingTraderCollateralDeficit.
    // Fuzzed global swing trader deficit
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralDeficit.selector
      ),
      abi.encode(stDeficit) // deficit is not 0
    );

    // Mock maltDataLab.maltToRewardDecimals(deficit)
    // This isn't strictly accurate but the units are consistent through this test
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(
        MaltDataLab.maltToRewardDecimals.selector,
        stDeficit
      ),
      abi.encode(stDeficit)
    );

    // Mock rewardThrottle.runwayDeficit.
    // Fuzzed runway deficit
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.runwayDeficit.selector),
      abi.encode(runwayDeficit) // deficit is not 0
    );

    // Mock maltDataLab.maltToRewardDecimals
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(MaltDataLab.maltToRewardDecimals.selector, 0),
      abi.encode(0)
    );

    // Mock globalIC.swingTraderCollateralRatio
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralRatio.selector
      ),
      abi.encode(0) // any value above 0 is fine as below local ratio is defined as 0
    );

    uint256 ratio = 1000;
    vm.mockCall(
      impliedCollateralService,
      abi.encodeWithSelector(
        ImpliedCollateralService.swingTraderCollateralRatio.selector
      ),
      abi.encode(ratio)
    );

    /*
     * Execution
     */
    uint256 totalDeficit = uint256(runwayDeficit) + uint256(stDeficit);

    mintRewardToken(address(profitDistributor), profit);
    profitDistributor.handleProfit(profit);

    /*
     * Assertions
     */
    uint256 swingTraderFinalBalance = rewardToken.balanceOf(swingTrader);
    uint256 throttleFinalBalance = rewardToken.balanceOf(rewardThrottle);
    uint256 treasuryFinalBalance = rewardToken.balanceOf(treasury);

    uint256 lpThrottleBps = profitDistributor.lpThrottleBps();
    uint256 distributionCut = (profit * distributionBps) / 10000;
    uint256 lpCut = (((distributionCut * runwayDeficit) / totalDeficit) *
      (10000 - lpThrottleBps)) / 10000;
    assertEq(throttleFinalBalance, lpCut);
    assertEq(swingTraderFinalBalance, distributionCut - lpCut);
    assertEq(treasuryFinalBalance, profit - distributionCut);
  }

  function testDaoRewardCut(
    uint256 profit,
    uint256 decimals,
    uint256 daoRewardCutBps,
    uint256 lpThrottleBps
  ) public {
    decimals = bound(decimals, 3, 36);
    profit = bound(profit, 10**decimals, 10**40); // larger than $1
    daoRewardCutBps = bound(daoRewardCutBps, 1, 10000);
    lpThrottleBps = bound(lpThrottleBps, 1, 10000);
    rewardToken.setDecimals(decimals);
    vm.prank(admin);
    profitDistributor.setDaoCut(daoRewardCutBps);
    vm.prank(admin);
    profitDistributor.setLpThrottleBps(lpThrottleBps);

    uint256 distributionBps = profitDistributor.distributeBps();

    /*
     * MOCKS
     */
    // Mock rewardThrottle.checkRewardUnderflow
    // Returns nothing. Needs to be mocked so it doesn't fail
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.checkRewardUnderflow.selector),
      ""
    );

    // Mock liquidityExtension.collateralDeficit. 0 deficit
    // LE has 0 deficit, so takes nothing. All rewards continue downstream
    vm.mockCall(
      liquidityExtension,
      abi.encodeWithSelector(LiquidityExtension.collateralDeficit.selector),
      abi.encode(0, decimals)
    );

    // mock auction.allocateArbRewards
    // Returns full profit. Meaning 0 allocated to arb
    vm.mockCall(
      auction,
      abi.encodeWithSelector(Auction.allocateArbRewards.selector),
      abi.encode(profit)
    );

    // Mock maltDataLab.priceTarget
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.priceTarget.selector),
      abi.encode(10**decimals)
    );

    // Mock globalIC.swingTraderCollateralDeficit.
    uint256 stDeficit = rewardToMaltDecimals(profit, decimals);
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(
        GlobalImpliedCollateralService.swingTraderCollateralDeficit.selector
      ),
      abi.encode(stDeficit) // deficit is not 0
    );

    // Mock maltDataLab.maltToRewardDecimals(deficit)
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(
        MaltDataLab.maltToRewardDecimals.selector,
        stDeficit
      ),
      abi.encode(stDeficit)
    );

    // Mock rewardThrottle.runwayDeficit.
    vm.mockCall(
      rewardThrottle,
      abi.encodeWithSelector(RewardThrottle.runwayDeficit.selector),
      abi.encode(0)
    );

    // Mock maltDataLab.maltToRewardDecimals
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(MaltDataLab.maltToRewardDecimals.selector, 0),
      abi.encode(0)
    );

    /*
     * Execution
     */
    mintRewardToken(address(profitDistributor), profit);
    profitDistributor.handleProfit(profit);

    /*
     * Assertions
     */
    uint256 daoFinalBalance = rewardToken.balanceOf(dao);
    uint256 swingTraderFinalBalance = rewardToken.balanceOf(swingTrader);
    uint256 throttleFinalBalance = rewardToken.balanceOf(rewardThrottle);
    uint256 treasuryFinalBalance = rewardToken.balanceOf(treasury);

    uint256 lpThrottleBps = profitDistributor.lpThrottleBps();
    uint256 distributionCut = (profit * distributionBps) / 10000;
    uint256 daoCut = (distributionCut * daoRewardCutBps) / 10000;
    assertEq(daoFinalBalance, daoCut);
    assertEq(swingTraderFinalBalance, distributionCut - daoCut);
    assertEq(throttleFinalBalance, 0);
    assertEq(treasuryFinalBalance, profit - distributionCut);
  }
}
