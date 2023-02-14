// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "../contracts/StabilityPod/ImpliedCollateralService.sol";
import "../contracts/StabilityPod/PoolCollateral.sol";
import "./DeployedStabilizedPool.sol";

contract ImpliedCollateralServiceTest is DeployedStabilizedPool {
  ImpliedCollateralService impliedCollateralService;
  
  function setUp() public {
    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    impliedCollateralService = ImpliedCollateralService(
        currentPool.core.impliedCollateralService
    );
  }

  function testGetCollateralizedMalt(
    uint256 overflowBalance,
    uint256 liquidityExtensionBalance,
    uint256 swingTraderBalance,
    uint256 swingTraderMaltBalance
  ) public {
    overflowBalance = bound(overflowBalance, 0, 2**100);
    liquidityExtensionBalance = bound(liquidityExtensionBalance, 0, 2**100);
    swingTraderBalance = bound(swingTraderBalance, 0, 2**100);
    swingTraderMaltBalance = bound(swingTraderMaltBalance, 0, 2**100);

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    // setup balances in contracts 
    // rewardOverflow
    mintRewardToken(currentPool.rewardSystem.rewardOverflow, overflowBalance);
    // liquidityExtension
    mintRewardToken(currentPool.core.liquidityExtension, liquidityExtensionBalance);
    // swingTrader
    mintRewardToken(currentPool.core.swingTrader, swingTraderBalance);
    // swingTraderMalt
    mintMalt(currentPool.core.swingTrader, swingTraderMaltBalance);

    // call getCollateralizedMalt
    PoolCollateral memory poolCollateral = impliedCollateralService.getCollateralizedMalt();

    // test that the returned PoolCollateral is correct
    assertEq(poolCollateral.lpPool, currentPool.pool);
    assertEq(poolCollateral.total, overflowBalance + liquidityExtensionBalance + swingTraderBalance);
    assertEq(poolCollateral.rewardOverflow, overflowBalance);
    assertEq(poolCollateral.liquidityExtension, liquidityExtensionBalance);
    assertEq(poolCollateral.swingTrader, swingTraderBalance);
    assertEq(poolCollateral.swingTraderMalt, swingTraderMaltBalance);
    assertEq(poolCollateral.arbTokens, 0);
  }
}
