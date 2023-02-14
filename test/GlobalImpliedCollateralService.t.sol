// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "../contracts/GlobalImpliedCollateralService.sol";

contract GlobalImpliedCollateralServiceTest is MaltTest {
  GlobalImpliedCollateralService globalIC;

  address deployer = nextAddress();
  address lpToken = nextAddress();
  address updater = nextAddress();
  address updaterManager = nextAddress();
  address poolFactory = nextAddress();

  function setUp() public {
    globalIC = new GlobalImpliedCollateralService(
      address(repository),
      admin,
      address(malt),
      deployer
    );
    vm.mockCall(
      poolFactory,
      abi.encodeWithSelector(IStabilizedPoolFactory.getPool.selector, lpToken),
      abi.encode(address(rewardToken), updater, "")
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
    vm.prank(admin);
    malt.setGlobalImpliedCollateralService(address(globalIC));
  }

  function testInitialConditions() public {
  }

  function testSetPoolUpdater(address pool, address updater) public {
    vm.assume(pool != address(0));
    vm.assume(updater != address(0));
    vm.expectRevert("Only deployer");
    globalIC.setUpdaterManager(updaterManager); 
    vm.prank(deployer);
    globalIC.setUpdaterManager(updaterManager); 

    vm.expectRevert("Must have updater manager role");
    globalIC.setPoolUpdater(pool, updater);
    vm.prank(updaterManager);
    globalIC.setPoolUpdater(pool, updater);
  }

  function testSetPoolUpdaterAddrZeroFails() public {
    address updater = address(0);
    vm.prank(deployer);
    globalIC.setUpdaterManager(updaterManager); 

    vm.prank(updaterManager);
    vm.expectRevert("GlobImpCol: No addr(0)");
    globalIC.setPoolUpdater(lpToken, updater);
  }

  function testMultipleSetPoolUpdater() public {
    vm.prank(deployer);
    globalIC.setUpdaterManager(updaterManager); 

    vm.prank(updaterManager);
    globalIC.setPoolUpdater(lpToken, updater);

    assertEq(
      globalIC.poolUpdatersLookup(lpToken),
      updater,
      "Pool updater lookup should be set"
    );
    assertEq(
      globalIC.poolUpdaters(updater),
      lpToken,
      "Pool updater should be set"
    );

    address newUpdater = address(5678);
    vm.prank(updaterManager);
    globalIC.setPoolUpdater(lpToken, newUpdater);

    assertEq(
      globalIC.poolUpdatersLookup(lpToken),
      newUpdater,
      "Pool updater lookup should be updated"
    );
    assertEq(
      globalIC.poolUpdaters(updater),
      address(0),
      "Old pool updater should be addr(0)"
    );
    assertEq(
      globalIC.poolUpdaters(newUpdater),
      lpToken,
      "Pool updater should have updated"
    );
  }

  function testSyncingCollateral(
    uint256 rewardOverflow,
    uint256 liquidityExtension,
    uint256 swingTrader,
    uint256 swingTraderMalt,
    uint256 arbTokens
  ) public {
    rewardOverflow = bound(rewardOverflow, 0, 2**50);
    liquidityExtension = bound(liquidityExtension, 0, 2**50);
    swingTrader = bound(swingTrader, 0, 2**50);
    vm.prank(deployer);
    globalIC.setUpdaterManager(updaterManager); 

    vm.prank(updaterManager);
    globalIC.setPoolUpdater(lpToken, updater);

    PoolCollateral memory collateral = PoolCollateral({
      lpPool: lpToken,
      total: rewardOverflow + liquidityExtension + swingTrader,
      rewardOverflow: rewardOverflow,
      liquidityExtension: liquidityExtension,
      swingTrader: swingTrader,
      swingTraderMalt: swingTraderMalt,
      arbTokens: arbTokens
    });
    vm.expectRevert("GlobImpCol: Unknown pool");
    globalIC.sync(collateral);
    vm.prank(updater);
    globalIC.sync(collateral);

    // Check global values are set
    (
      uint256 total,
      uint256 rewardOverflow,
      uint256 liquidityExtension,
      uint256 swingTrader,
      uint256 swingTraderMalt,
      uint256 arbTokens
    ) = globalIC.collateral();

    assertEq(total, collateral.total, "Total should be set");
    assertEq(
      rewardOverflow,
      collateral.rewardOverflow,
      "Reward overflow should be set"
    );
    assertEq(
      liquidityExtension,
      collateral.liquidityExtension,
      "Liquidity extension should be set"
    );
    assertEq(swingTrader, collateral.swingTrader, "Swing trader should be set");
    assertEq(
      swingTraderMalt,
      collateral.swingTraderMalt,
      "Swing trader malt should be set"
    );
    assertEq(arbTokens, collateral.arbTokens, "Arb tokens should be set");
    assertEq(globalIC.totalPhantomMalt(), collateral.swingTraderMalt, "Total phantom malt should return swing trader malt");

    // Check pool values are set
    (
      address _lpPool,
      uint256 _total,
      uint256 _rewardOverflow,
      uint256 _liquidityExtension,
      uint256 _swingTrader,
      uint256 _swingTraderMalt,
      uint256 _arbTokens
    ) = globalIC.poolCollateral(lpToken);

    assertEq(_lpPool, lpToken, "lpPool should be set");
    assertEq(_total, collateral.total, "Total should be set");
    assertEq(
      _rewardOverflow,
      collateral.rewardOverflow,
      "Reward overflow should be set"
    );
    assertEq(
      _liquidityExtension,
      collateral.liquidityExtension,
      "Liquidity extension should be set"
    );
    assertEq(_swingTrader, collateral.swingTrader, "Swing trader should be set");
    assertEq(
      _swingTraderMalt,
      collateral.swingTraderMalt,
      "Swing trader malt should be set"
    );
    assertEq(_arbTokens, collateral.arbTokens, "Arb tokens should be set");
  }

  function testCollateralRatio(
    uint256 desiredRatio,
    uint256 totalSupply
  ) public {
    desiredRatio = bound(desiredRatio, 0, 20_000); // up to 200%
    totalSupply = bound(totalSupply, 200_000, 2**100); // just enough resolution

    assertEq(globalIC.collateralRatio(), 0, "Collateral ratio should be 0");
     
    mintMalt(address(1234), totalSupply);

    vm.prank(deployer);
    globalIC.setUpdaterManager(updaterManager); 

    vm.prank(updaterManager);
    globalIC.setPoolUpdater(lpToken, updater);

    PoolCollateral memory collateral = PoolCollateral({
      lpPool: lpToken,
      total: totalSupply * desiredRatio / 10000,
      // Everything else isn't needed here
      rewardOverflow: 0,
      liquidityExtension: 0,
      swingTrader: 0,
      swingTraderMalt: 0,
      arbTokens: 0
    });
    vm.prank(updater);
    globalIC.sync(collateral);

    uint256 collateralRatio = globalIC.collateralRatio();

    assertApproxEqRel(
      collateralRatio,
      1e18 * desiredRatio / 10_000,
      1e16 // 1%
    );
  }

  function testSwingTraderCollateralRatio(
    uint256 desiredRatio,
    uint256 totalSupply
  ) public {
    desiredRatio = bound(desiredRatio, 0, 20_000); // up to 200%
    totalSupply = bound(totalSupply, 200_000, 2**100); // just enough resolution

    assertEq(globalIC.swingTraderCollateralRatio(), 0, "Collateral ratio should be 0");
     
    mintMalt(address(1234), totalSupply);

    vm.prank(deployer);
    globalIC.setUpdaterManager(updaterManager); 

    vm.prank(updaterManager);
    globalIC.setPoolUpdater(lpToken, updater);

    PoolCollateral memory collateral = PoolCollateral({
      lpPool: lpToken,
      swingTrader: totalSupply * desiredRatio / 10000,
      // Everything else isn't needed here
      total: 0,
      rewardOverflow: 0,
      liquidityExtension: 0,
      swingTraderMalt: 0,
      arbTokens: 0
    });
    vm.prank(updater);
    globalIC.sync(collateral);

    uint256 swingTraderCollateralRatio = globalIC.swingTraderCollateralRatio();

    assertApproxEqRel(
      swingTraderCollateralRatio,
      1e18 * desiredRatio / 10_000,
      1e16 // 1%
    );
  }

  function testSwingTraderCollateralDeficit(
    uint256 desiredDeficit,
    uint256 totalSupply
  ) public {
    totalSupply = bound(totalSupply, 0, 2**100);
    desiredDeficit = bound(desiredDeficit, 0, totalSupply);

    assertEq(globalIC.swingTraderCollateralDeficit(), 0, "Collateral deficit should be 0");
     
    mintMalt(address(1234), totalSupply);

    vm.prank(deployer);
    globalIC.setUpdaterManager(updaterManager); 

    vm.prank(updaterManager);
    globalIC.setPoolUpdater(lpToken, updater);

    PoolCollateral memory collateral = PoolCollateral({
      lpPool: lpToken,
      swingTrader: totalSupply - desiredDeficit,
      // Everything else isn't needed here
      total: 0,
      rewardOverflow: 0,
      liquidityExtension: 0,
      swingTraderMalt: 0,
      arbTokens: 0
    });
    vm.prank(updater);
    globalIC.sync(collateral);

    uint256 swingTraderCollateralDeficit = globalIC.swingTraderCollateralDeficit();

    assertEq(
      swingTraderCollateralDeficit,
      desiredDeficit
    );
  }
}
