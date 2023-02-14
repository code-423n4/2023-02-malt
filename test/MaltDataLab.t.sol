// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "../contracts/DataFeed/MaltDataLab.sol";
import "../contracts/GlobalImpliedCollateralService.sol";
import "../contracts/StabilityPod/SwingTraderManager.sol";
import "./MaltTest.sol";

contract MaltDataLabTest is MaltTest {
  using stdStorage for StdStorage;

  MaltDataLab maltDataLab;

  address poolFactory = nextAddress();
  address stakeToken = nextAddress();
  address poolMA = nextAddress();
  address ratioMA = nextAddress();
  address impliedCollateralService = nextAddress();
  address swingTraderManager = nextAddress();
  address globalIC = nextAddress();
  address trustedUpdater = nextAddress();
  address updater = nextAddress();
  
  function setUp() public {
    maltDataLab = new MaltDataLab(
      timelock,
      address(repository),
      poolFactory
    );
    vm.mockCall(
      poolFactory,
      abi.encodeWithSelector(IStabilizedPoolFactory.getPool.selector, stakeToken),
      abi.encode(address(rewardToken), updater, "")
    );
    vm.prank(poolFactory);
    maltDataLab.setupContracts(
      address(malt),
      address(rewardToken),
      stakeToken,
      poolMA,
      ratioMA,
      impliedCollateralService,
      swingTraderManager,
      globalIC,
      trustedUpdater
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

  function testSwingTraderEntryPriceFullyCollateralized() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent) // 100% in Malt.decimals()
    );

    uint256 entryPrice = maltDataLab.getSwingTraderEntryPrice();
    assertEq(entryPrice, priceTarget);
  }

  function testSwingTraderEntryPriceWithZeroMaltRatio(uint256 collateralRatio) public {
    collateralRatio = bound(collateralRatio, 1, 100);

    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent * collateralRatio / 100) 
    );
    vm.mockCall(
      swingTraderManager,
      abi.encodeWithSelector(SwingTraderManager.calculateSwingTraderMaltRatio.selector),
      abi.encode(0) 
    );

    uint256 entryPrice = maltDataLab.getSwingTraderEntryPrice();
    assertEq(entryPrice, priceTarget);
  }

  function testSwingTraderEntryPrice1() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent * 70 / 100) // 70% in Malt.decimals()
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      swingTraderManager,
      abi.encodeWithSelector(SwingTraderManager.calculateSwingTraderMaltRatio.selector),
      abi.encode(rewardHundyPercent * 15 / 100) // 15% in Reward.decimals() 
    );

    uint256 entryPrice = maltDataLab.getSwingTraderEntryPrice();
    // This magic number is the result of manually calculating the entry priceTarget
    // using maltRatio = 15%, collateralRatio = 70%, and z = 20
    assertApproxEqAbs(entryPrice, 736138748144123863, rewardHundyPercent * 1 / 1000); // 0.1% 
  }

  function testSwingTraderEntryPrice2() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent * 70 / 100) // 70% in Malt.decimals()
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      swingTraderManager,
      abi.encodeWithSelector(SwingTraderManager.calculateSwingTraderMaltRatio.selector),
      abi.encode(rewardHundyPercent * 5 / 100) // 5% in Reward.decimals() 
    );

    uint256 entryPrice = maltDataLab.getSwingTraderEntryPrice();
    // This magic number is the result of manually calculating the entry priceTarget
    // using maltRatio = 5%, collateralRatio = 70%, and z = 20
    assertApproxEqAbs(entryPrice, 874020213662505837, rewardHundyPercent * 1 / 1000); // 0.1% 
  }

  function testSwingTraderEntryPrice3() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent * 70 / 100) // 70% in Malt.decimals()
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      swingTraderManager,
      abi.encodeWithSelector(SwingTraderManager.calculateSwingTraderMaltRatio.selector),
      abi.encode(rewardHundyPercent * 40 / 100) // 40% in Reward.decimals() 
    );

    uint256 entryPrice = maltDataLab.getSwingTraderEntryPrice();
    // This magic number is the result of manually calculating the entry priceTarget
    // using maltRatio = 40%, collateralRatio = 70%, and z = 20
    assertApproxEqAbs(entryPrice, 643243243243243243, rewardHundyPercent * 1 / 1000); // 0.1% 
  }

  function testSwingTraderEntryPrice4() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.prank(admin);
    maltDataLab.setZ(40);
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent * 70 / 100) // 70% in Malt.decimals()
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      swingTraderManager,
      abi.encodeWithSelector(SwingTraderManager.calculateSwingTraderMaltRatio.selector),
      abi.encode(rewardHundyPercent * 25 / 100) // 25% in Reward.decimals() 
    );

    uint256 entryPrice = maltDataLab.getSwingTraderEntryPrice();
    // This magic number is the result of manually calculating the entry priceTarget
    // using maltRatio = 25%, collateralRatio = 70%, and z = 40
    assertApproxEqAbs(entryPrice, 760695887297096723, rewardHundyPercent * 1 / 1000); // 0.1% 
  }

  function testSwingTraderEntryPriceIntersection(uint256 newZ) public {
    newZ = bound(newZ, 1, 100);
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;
    uint256 collateralRatio = hundyPercent * 70 / 100; // 70% in Malt.decimals()

    vm.prank(admin);
    maltDataLab.setZ(newZ);
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(collateralRatio)
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      swingTraderManager,
      abi.encodeWithSelector(SwingTraderManager.calculateSwingTraderMaltRatio.selector),
      abi.encode(rewardHundyPercent * newZ / 100)
    );

    uint256 entryPrice = maltDataLab.getSwingTraderEntryPrice();
    // By setting malt ratio to newZ we should always get the entry price to be the collateralRatio
    assertApproxEqAbs(entryPrice, collateralRatio, rewardHundyPercent * 1 / 1000); // 0.1% 
  }
  
  function testGetActualPriceTargetFullyCollateralized() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent) // 100% in Malt.decimals()
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      ratioMA,
      abi.encodeWithSelector(DualMovingAverage.getValueWithLookback.selector, 4 hours),
      abi.encode(rewardHundyPercent * 40 / 100) // 40% in Reward.decimals() 
    );

    uint256 actualPriceTarget = maltDataLab.getActualPriceTarget();
    assertEq(actualPriceTarget, priceTarget);
  }

  function testGetActualPriceTargetBeforeBreakpoint() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent * 70 / 100) // 70% in Malt.decimals()
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      ratioMA,
      abi.encodeWithSelector(DualMovingAverage.getValueWithLookback.selector, 4 hours),
      abi.encode(rewardHundyPercent * 5 / 100) // 5% in Reward.decimals() 
    );

    uint256 actualPriceTarget = maltDataLab.getActualPriceTarget();
    // Because breakpointBps is 50% and z is 20 actual price only starts to
    // drop at a value of 10% but current malt Ratio is 5% so we should get 
    // the priceTarget
    assertApproxEqAbs(actualPriceTarget, priceTarget, rewardHundyPercent * 1 / 1000); // 0.1% 
  }

  function testGetActualPriceTarget() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(hundyPercent * 70 / 100) // 70% in Malt.decimals()
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      ratioMA,
      abi.encodeWithSelector(DualMovingAverage.getValueWithLookback.selector, 4 hours),
      abi.encode(rewardHundyPercent * 15 / 100) // 15% in Reward.decimals() 
    );

    uint256 actualPriceTarget = maltDataLab.getActualPriceTarget();
    // This magic number is the result of manually calculating the actual priceTarget
    // using maltRatio = 15%, collateralRatio = 70%, and z = 20
    assertApproxEqAbs(actualPriceTarget, 850000000000000000, rewardHundyPercent * 1 / 1000); // 0.1% 
  }

  function testGetActualPriceTargetAboveMaltRatioSaturation() public {
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;
    uint256 collateralRatio = hundyPercent * 70 / 100; // 70% in Malt.decimals()

    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(collateralRatio)
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      ratioMA,
      abi.encodeWithSelector(DualMovingAverage.getValueWithLookback.selector, 4 hours),
      abi.encode(rewardHundyPercent * 25 / 100) // 15% in Reward.decimals() 
    );

    uint256 actualPriceTarget = maltDataLab.getActualPriceTarget();
    // The malt ratio is above the value of z, therefore actual price target
    // should be equal to the collateral ratio
    assertApproxEqAbs(actualPriceTarget, collateralRatio, rewardHundyPercent * 1 / 1000); // 0.1% 
  }

  function testGetActualPriceTargetIntersection(uint256 newZ) public {
    newZ = bound(newZ, 1, 99);
    uint256 priceTarget = maltDataLab.priceTarget();
    uint256 hundyPercent = 10**18;
    uint256 collateralRatio = hundyPercent * 70 / 100; // 70% in Malt.decimals()

    vm.prank(admin);
    maltDataLab.setZ(newZ);
    vm.mockCall(
      globalIC,
      abi.encodeWithSelector(GlobalImpliedCollateralService.collateralRatio.selector),
      abi.encode(collateralRatio)
    );
    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      ratioMA,
      abi.encodeWithSelector(DualMovingAverage.getValueWithLookback.selector, 4 hours),
      abi.encode(rewardHundyPercent * newZ / 100)
    );

    uint256 actualPriceTarget = maltDataLab.getActualPriceTarget();
    // Because the malt ratio is equal to z then we should always get 
    // a price target equal to the collateral ratio
    assertApproxEqAbs(actualPriceTarget, collateralRatio, rewardHundyPercent * 1 / 1000); // 0.1% 
  }

  function testGetRealBurnBudgetSaturated(
    uint256 premiumExcess,
    uint256 maxSpend,
    uint256 newZ
  ) public {
    premiumExcess = bound(premiumExcess, 1 ether, 2**100);
    maxSpend = bound(maxSpend, premiumExcess, 2**100);
    newZ = bound(newZ, 5, 99);

    vm.prank(admin);
    maltDataLab.setZ(newZ);

    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      swingTraderManager,
      abi.encodeWithSelector(SwingTraderManager.calculateSwingTraderMaltRatio.selector),
      abi.encode(rewardHundyPercent * newZ * 2 / 100) // larger than z%
    );

    uint256 burnBudget = maltDataLab.getRealBurnBudget(maxSpend, premiumExcess);
    assertEq(burnBudget, maxSpend);
  }

  function testGetRealBurnBudgetUnsaturated(
    uint256 premiumExcess,
    uint256 maxSpend,
    uint256 newZ,
    uint256 bps
  ) public {
    premiumExcess = bound(premiumExcess, 1 ether, 2**100);
    maxSpend = bound(maxSpend, premiumExcess, 2**100);
    newZ = bound(newZ, 10, 99);
    bps = bound(bps, 10, 99);

    vm.prank(admin);
    maltDataLab.setZ(newZ);

    uint256 rewardHundyPercent = 10 ** rewardToken.decimals();
    vm.mockCall(
      swingTraderManager,
      abi.encodeWithSelector(SwingTraderManager.calculateSwingTraderMaltRatio.selector),
      abi.encode(rewardHundyPercent * newZ * bps / 100 / 100) // bps of z%
    );

    uint256 burnBudget = maltDataLab.getRealBurnBudget(maxSpend, premiumExcess);
    uint256 delta = maxSpend - premiumExcess;
    assertApproxEqRel(burnBudget, premiumExcess + delta * bps / 100, rewardHundyPercent * 1 / 1000); // 0.1%
  }

  function testGetRealBurnBudgetSmallMaxBurn(
    uint256 premiumExcess,
    uint256 maxSpend
  ) public {
    premiumExcess = bound(premiumExcess, 0, 2**100);
    maxSpend = bound(maxSpend, 0, premiumExcess);

    uint256 burnBudget = maltDataLab.getRealBurnBudget(maxSpend, premiumExcess);

    assertEq(burnBudget, maxSpend);
  }

  function testRoundTripLargerRewardDecimalConversion(
    uint256 decimals,
    uint256 amount
  ) public {
    decimals = bound(decimals, 18, 36);
    amount = bound(amount, 0, 2**100);
    rewardToken.setDecimals(decimals);

    uint256 converted = maltDataLab.maltToRewardDecimals(amount);
    uint256 roundTrip = maltDataLab.rewardToMaltDecimals(converted);

    assertEq(roundTrip, amount);
  }

  function testRoundTripSmallerRewardDecimalConversion(
    uint256 decimals,
    uint256 amount
  ) public {
    decimals = bound(decimals, 6, 18);
    amount = bound(amount, 0, 2**100);
    rewardToken.setDecimals(decimals);

    uint256 converted = maltDataLab.rewardToMaltDecimals(amount);
    uint256 roundTrip = maltDataLab.maltToRewardDecimals(converted);

    assertEq(roundTrip, amount);
  }

  function testRewardToMaltDecimals(uint256 decimals) public {
    decimals = bound(decimals, 6, 36);
    rewardToken.setDecimals(decimals);

    uint256 converted = maltDataLab.rewardToMaltDecimals(10**decimals);

    assertEq(converted, 1e18);

    uint256 roundTrip = maltDataLab.maltToRewardDecimals(converted);

    assertEq(roundTrip, 10**decimals);
  }

  function testMaltToRewardDecimals(uint256 decimals) public {
    decimals = bound(decimals, 6, 36);
    rewardToken.setDecimals(decimals);
    
    uint256 converted = maltDataLab.maltToRewardDecimals(1e18);

    assertEq(converted, 10**decimals);

    uint256 roundTrip = maltDataLab.rewardToMaltDecimals(converted);

    assertEq(roundTrip, 1e18);
  }
}
