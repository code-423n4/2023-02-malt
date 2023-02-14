// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./DeployedStabilizedPool.sol";
import "../contracts/StabilityPod/StabilizerNode.sol";


contract StabilizerNodeTest is DeployedStabilizedPool {
  StabilizerNode stabilizerNode;
  MaltDataLab maltDataLab;

  function setUp() public {
    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    stabilizerNode = StabilizerNode(currentPool.core.stabilizerNode);
    maltDataLab = MaltDataLab(currentPool.periphery.dataLab);
  }

  function testOnlyEoaCanCallStabilize() public {
    vm.expectRevert("Perm: Only EOA");
    stabilizerNode.stabilize();
  }

  function testStabilizeDoesNothingInitially() public {
    vm.prank(tx.origin);
    stabilizerNode.stabilize();
  }

  function _buyMalt(uint256 amount, address destination) internal {
    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    IDexHandler dexHandler = IDexHandler(currentPool.periphery.dexHandler);

    mintRewardToken(address(dexHandler), amount); 

    vm.prank(timelock);
    dexHandler.buyMalt(amount, 10000); // infinite slippage

    uint256 maltBalance = malt.balanceOf(timelock);

    vm.prank(timelock);
    malt.transfer(destination, maltBalance);
  }

  function _sellMalt(uint256 amount, address destination) internal {
    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    IDexHandler dexHandler = IDexHandler(currentPool.periphery.dexHandler);

    mintMalt(address(dexHandler), amount); 

    vm.prank(timelock);
    dexHandler.sellMalt(amount, 10000); // infinite slippage

    uint256 balance = rewardToken.balanceOf(timelock);

    vm.prank(timelock);
    rewardToken.transfer(destination, balance);
  }

  function testStabilizeAbovePeg() public {
    // Boost the price up so we need to stabilize
    _buyMalt(10_000e18, user);

    StabilizedPool memory currentPool = getCurrentStabilizedPool();
    IDexHandler dexHandler = IDexHandler(currentPool.periphery.dexHandler);

    // Fetch live price so we can mock the price average
    // Keeping them the same keeps the test simple
    (uint256 livePrice,) = dexHandler.maltMarketPrice();

    vm.mockCall(
      address(maltDataLab),
      abi.encodeWithSelector(IMaltDataLab.maltPriceAverage.selector),
      abi.encode(livePrice)
    );
    vm.prank(tx.origin);
    stabilizerNode.stabilize();

    (livePrice,) = dexHandler.maltMarketPrice();

    // Price has been stabilized
    assertApproxEqRel(livePrice, 1e18, 1e16);
  }

  function testStabilizeBelowPegSwingTrader() public {
    // Drop the price so we need to stabilize
    _sellMalt(10_000e18, user);

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    // Mint some collateral
    mintRewardToken(currentPool.core.swingTrader, 100_000e18);

    ImpliedCollateralService impliedCollateralService = ImpliedCollateralService(currentPool.core.impliedCollateralService);
    impliedCollateralService.syncGlobalCollateral();

    IDexHandler dexHandler = IDexHandler(currentPool.periphery.dexHandler);

    // Fetch live price so we can mock the price average
    // Keeping them the same keeps the test simple
    (uint256 livePrice,) = dexHandler.maltMarketPrice();

    vm.mockCall(
      address(maltDataLab),
      abi.encodeWithSelector(IMaltDataLab.maltPriceAverage.selector),
      abi.encode(livePrice)
    );
    vm.prank(tx.origin);
    stabilizerNode.stabilize();

    (livePrice,) = dexHandler.maltMarketPrice();

    // Price has been stabilized
    assertApproxEqRel(livePrice, 1e18, 1e16);
  }

  function testStabilizeBelowPegAuction() public {
    // Drop the price so we need to stabilize
    _sellMalt(10_000e18, user);

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    ImpliedCollateralService impliedCollateralService = ImpliedCollateralService(currentPool.core.impliedCollateralService);
    impliedCollateralService.syncGlobalCollateral();

    IDexHandler dexHandler = IDexHandler(currentPool.periphery.dexHandler);

    // Fetch live price so we can mock the price average
    // Keeping them the same keeps the test simple
    (uint256 livePrice,) = dexHandler.maltMarketPrice();

    vm.mockCall(
      address(maltDataLab),
      abi.encodeWithSelector(IMaltDataLab.maltPriceAverage.selector),
      abi.encode(livePrice)
    );
    vm.prank(tx.origin);
    stabilizerNode.stabilize();

    Auction auction = Auction(currentPool.core.auction);
  
    bool hasAuction = auction.hasOngoingAuction();
    assertTrue(hasAuction);
  }

  function testTrackPool() public {
    stabilizerNode.trackPool();
    vm.expectRevert("Too early");
    stabilizerNode.trackPool();
  }

  function testSuccessiveStabilizes() public {
    vm.prank(tx.origin);
    stabilizerNode.stabilize();
    vm.prank(tx.origin);
    vm.expectRevert("Can't call stabilize");
    stabilizerNode.stabilize();

    // Catch another execution branch
    vm.warp(block.timestamp + 35); // beyond fastAveragePeriod
    vm.expectRevert("Can't call stabilize");
    vm.prank(tx.origin);
    stabilizerNode.stabilize();
  }

  function testAutoEndAuction() public {
    // Drop the price so we need to stabilize
    _sellMalt(10_000e18, user);

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    ImpliedCollateralService impliedCollateralService = ImpliedCollateralService(currentPool.core.impliedCollateralService);
    impliedCollateralService.syncGlobalCollateral();

    IDexHandler dexHandler = IDexHandler(currentPool.periphery.dexHandler);

    // Fetch live price so we can mock the price average
    // Keeping them the same keeps the test simple
    (uint256 livePrice,) = dexHandler.maltMarketPrice();

    vm.mockCall(
      address(maltDataLab),
      abi.encodeWithSelector(IMaltDataLab.maltPriceAverage.selector),
      abi.encode(livePrice)
    );
    vm.prank(tx.origin);
    stabilizerNode.stabilize();

    Auction auction = Auction(currentPool.core.auction);
  
    bool hasAuction = auction.hasOngoingAuction();
    assertTrue(hasAuction);

    (
      uint256 auctionId,
      uint256 maxCommitments,
      uint256 commitments,
      uint256 maltPurchased,
      uint256 startingPrice,
      uint256 endingPrice,
      uint256 finalPrice,
      uint256 pegPrice,
      uint256 startingTime,
      uint256 endingTime,
      uint256 finalBurnBudget
    ) = auction.getActiveAuction();

    mintRewardToken(user, maxCommitments);
    vm.prank(user);
    rewardToken.approve(address(auction), maxCommitments);
    vm.prank(user);
    // Auction not quite fully subscribed. 100 less than maxCommitments
    // The auction should be automatically ended anyway
    auction.purchaseArbitrageTokens(maxCommitments - 100, 0);

    (,,,,,,,,,bool active) = auction.getAuctionCore(auctionId);
    assertFalse(active);

    vm.expectRevert("No auction running");
    stabilizerNode.endAuctionEarly();
  }

  function testSetStabilizerBackoff() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setStabilizeBackoff(1);

    uint256 backoff = stabilizerNode.stabilizeBackoffPeriod();
    uint256 newBackoff = backoff + 2;
    vm.prank(admin);
    stabilizerNode.setStabilizeBackoff(newBackoff);

    uint256 finalBackoff = stabilizerNode.stabilizeBackoffPeriod();
    assertEq(finalBackoff, newBackoff);
  }

  function testSetDefaultIncentive() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setDefaultIncentive(200e18);

    uint256 incentive = stabilizerNode.defaultIncentive();
    uint256 newIncentive = incentive * 2;
    vm.prank(admin);
    stabilizerNode.setDefaultIncentive(newIncentive);

    uint256 finalIncentive = stabilizerNode.defaultIncentive();
    assertEq(finalIncentive, newIncentive);
  }

  function testSetTrackingIncentive() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setTrackingIncentive(200e18);

    uint256 incentive = stabilizerNode.trackingIncentive();
    uint256 newIncentive = incentive * 2;
    vm.prank(admin);
    stabilizerNode.setTrackingIncentive(newIncentive);

    uint256 finalIncentive = stabilizerNode.trackingIncentive();
    assertEq(finalIncentive, newIncentive);
  }

  function testSetExpansionDamping() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setExpansionDamping(8);

    uint256 damping = stabilizerNode.expansionDampingFactor();
    uint256 newDamping = damping * 2;
    vm.prank(admin);
    stabilizerNode.setExpansionDamping(newDamping);

    uint256 finalDamping = stabilizerNode.expansionDampingFactor();
    assertEq(finalDamping, newDamping);
  }

  function testSetStabilityThresholds(uint256 upper, uint256 lower) public {
    lower = bound(lower, 1, 9999);
    vm.assume(upper != 0);
    vm.expectRevert("Must have admin role");
    stabilizerNode.setStabilityThresholds(upper, lower);

    vm.prank(admin);
    stabilizerNode.setStabilityThresholds(upper, lower);

    uint256 fetchedUpper = stabilizerNode.upperStabilityThresholdBps();
    uint256 fetchedLower = stabilizerNode.lowerStabilityThresholdBps();
    assertEq(fetchedUpper, upper);
    assertEq(fetchedLower, lower);
  }

  function testSetSupplyDistributionController(address controller) public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setSupplyDistributionController(controller);

    vm.prank(admin);
    stabilizerNode.setSupplyDistributionController(controller);

    address fetchedController = stabilizerNode.supplyDistributionController();
    assertEq(fetchedController, controller);
  }

  function testSetAuctionStartController(address controller) public {
    vm.expectRevert("Must have admin privilege");
    stabilizerNode.setAuctionStartController(controller);

    vm.prank(admin);
    stabilizerNode.setAuctionStartController(controller);

    address fetchedController = stabilizerNode.auctionStartController();
    assertEq(fetchedController, controller);
  }

  function testSetPriceAveragePeriod() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setPriceAveragePeriod(60);

    uint256 period = stabilizerNode.priceAveragePeriod();
    uint256 newPeriod = period * 2;
    vm.prank(admin);
    stabilizerNode.setPriceAveragePeriod(newPeriod);

    uint256 finalPeriod = stabilizerNode.priceAveragePeriod();
    assertEq(finalPeriod, newPeriod);
  }

  function testOverrideDistance() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setOverrideDistance(1e13);

    uint256 distance = stabilizerNode.overrideDistanceBps();
    uint256 newDistance = distance * 2;
    vm.prank(admin);
    stabilizerNode.setOverrideDistance(newDistance);

    uint256 finalDistance = stabilizerNode.overrideDistanceBps();
    assertEq(finalDistance, newDistance);
  }

  function testFastAveragePeriod() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setFastAveragePeriod(66);

    uint256 period = stabilizerNode.fastAveragePeriod();
    uint256 newPeriod = period * 2;
    vm.prank(admin);
    stabilizerNode.setFastAveragePeriod(newPeriod);

    uint256 finalPeriod = stabilizerNode.fastAveragePeriod();
    assertEq(finalPeriod, newPeriod);
  }

  function testSetBandLimits(uint256 upper, uint256 lower) public {
    vm.assume(upper != 0);
    vm.assume(lower != 0);
    vm.expectRevert("Must have admin role");
    stabilizerNode.setBandLimits(upper, lower);

    vm.prank(admin);
    stabilizerNode.setBandLimits(upper, lower);

    uint256 fetchedUpper = stabilizerNode.upperBandLimitBps();
    uint256 fetchedLower = stabilizerNode.lowerBandLimitBps();
    assertEq(fetchedUpper, upper);
    assertEq(fetchedLower, lower);
  }

  function testSlippageBps() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setSlippageBps(777);

    uint256 slippage = stabilizerNode.sampleSlippageBps();
    uint256 newSlippage = slippage * 2;
    vm.prank(admin);
    stabilizerNode.setSlippageBps(newSlippage);

    uint256 finalSlippage = stabilizerNode.sampleSlippageBps();
    assertEq(finalSlippage, newSlippage);
  }

  function testSetSkipAuctionThreshold() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setSkipAuctionThreshold(1e8);

    uint256 threshold = stabilizerNode.skipAuctionThreshold();
    uint256 newThreshold = threshold * 2;
    vm.prank(admin);
    stabilizerNode.setSkipAuctionThreshold(newThreshold);

    uint256 finalThreshold = stabilizerNode.skipAuctionThreshold();
    assertEq(finalThreshold, newThreshold);
  }

  function testSetPreferAuctionThreshold() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setPreferAuctionThreshold(1e8);

    uint256 threshold = stabilizerNode.preferAuctionThreshold();
    uint256 newThreshold = threshold * 2;
    vm.prank(admin);
    stabilizerNode.setPreferAuctionThreshold(newThreshold);

    uint256 finalThreshold = stabilizerNode.preferAuctionThreshold();
    assertEq(finalThreshold, newThreshold);
  }

  function testSetTrackingBackoff() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setTrackingBackoff(1);

    uint256 backoff = stabilizerNode.trackingBackoff();
    uint256 newBackoff = backoff + 2;
    vm.prank(admin);
    stabilizerNode.setTrackingBackoff(newBackoff);

    uint256 finalBackoff = stabilizerNode.trackingBackoff();
    assertEq(finalBackoff, newBackoff);
  }

  function testSetTrackAfterStabilize(bool _track) public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setTrackAfterStabilize(_track);

    vm.prank(admin);
    stabilizerNode.setTrackAfterStabilize(_track);
  }

  function testSetOnlyStabilizeToPeg(bool _track) public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setOnlyStabilizeToPeg(_track);

    vm.prank(admin);
    stabilizerNode.setOnlyStabilizeToPeg(_track);

    bool finalize = stabilizerNode.onlyStabilizeToPeg();
    assertEq(finalize, _track);
  }

  function testSetCallerCut() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setCallerCut(1);

    uint256 cut = stabilizerNode.callerRewardCutBps();
    uint256 newCut = cut + 2;
    vm.prank(admin);
    stabilizerNode.setCallerCut(newCut);

    uint256 finalCut = stabilizerNode.callerRewardCutBps();
    assertEq(finalCut, newCut);
  }

  function testTogglePause() public {
    bool paused = stabilizerNode.paused();
    assertFalse(paused);

    vm.expectRevert("Must have admin role");
    stabilizerNode.togglePause();

    vm.prank(admin);
    stabilizerNode.togglePause();

    paused = stabilizerNode.paused();
    assertTrue(paused);
  }

  function testSetPrimedWindow() public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setPrimedWindow(1);

    uint256 window = stabilizerNode.primedWindow();
    uint256 newWindow = window + 2;
    vm.prank(admin);
    stabilizerNode.setPrimedWindow(newWindow);

    uint256 finalWindow = stabilizerNode.primedWindow();
    assertEq(finalWindow, newWindow);
  }

  function testUsePrimedWindow(bool _set) public {
    vm.expectRevert("Must have admin role");
    stabilizerNode.setUsePrimedWindow(_set);

    vm.prank(admin);
    stabilizerNode.setUsePrimedWindow(_set);

    bool finalSet = stabilizerNode.usePrimedWindow();
    assertEq(finalSet, _set);
  }
}
