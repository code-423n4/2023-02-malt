// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "./DeployedStabilizedPool.sol";
import "../../contracts/StabilizedPool/StabilizedPoolFactory.sol";
import "../../contracts/GlobalImpliedCollateralService.sol";
import "../../contracts/Timekeeper.sol";

contract StabilizedPoolFactoryTest is MaltTest {
  using stdStorage for StdStorage;

  StabilizedPoolFactory poolFactory;
  MaltTimekeeper timekeeper;
  GlobalImpliedCollateralService globalIC;

  address keeperRegistry = nextAddress();

  function setUp() public {
    globalIC = new GlobalImpliedCollateralService(
      address(repository),
      admin,
      address(malt),
      admin
    );

    timekeeper = new MaltTimekeeper(
      address(repository),
      60 * 120, // 2 hours
      block.timestamp,
      address(malt)
    );

    poolFactory = new StabilizedPoolFactory(
      address(repository),
      admin,
      address(malt),
      address(globalIC),
      address(transferService),
      address(timekeeper)
    );
    // treasury,
    // keeperRegistry

    vm.startPrank(admin);
    globalIC.setUpdaterManager(address(poolFactory));
    transferService.setVerifierManager(address(poolFactory));
    address[] memory minters = new address[](1);
    minters[0] = address(timekeeper);
    address[] memory burners = new address[](0);
    malt.setupContracts(
      address(globalIC),
      address(poolFactory),
      minters,
      burners
    );

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
    vm.stopPrank();
  }

  function testInitialContractAddresses() public {
    assertEq(address(poolFactory.globalIC()), address(globalIC));
    assertEq(address(poolFactory.transferService()), address(transferService));
    assertEq(poolFactory.timekeeper(), address(timekeeper));
    assertEq(poolFactory.malt(), address(malt));
  }

  function testInitializingNewPool(address randomUser) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    address pool = nextAddress();
    address updater = nextAddress();
    string memory name = "My Test Pool";

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolFactory.initializeStabilizedPool(
      pool,
      name,
      address(rewardToken),
      updater
    );

    vm.prank(admin);
    poolFactory.initializeStabilizedPool(
      pool,
      name,
      address(rewardToken),
      updater
    );

    vm.prank(admin);
    vm.expectRevert("already initialized");
    poolFactory.initializeStabilizedPool(
      pool,
      name,
      address(rewardToken),
      updater
    );

    (
      address collateralToken,
      address poolUpdater,
      string memory poolName
    ) = poolFactory.getPool(pool);

    assertEq(collateralToken, address(rewardToken));
    assertEq(poolName, name);
    assertEq(poolUpdater, updater);
  }

  // function testDeployingAuction() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployAuction(pool, 10**18);

  //   vm.prank(admin);
  //   poolFactory.deployAuction(pool, 10**18);

  //   vm.prank(admin);
  //   vm.expectRevert("Auction already deployed");
  //   poolFactory.deployAuction(pool, 10**18);

  //   (
  //     address auction,
  //     address auctionEscapeHatch,
  //     address impliedCollateralService,
  //     address liquidityExtension,
  //     address profitDistributor,
  //     address stabilizerNode,
  //     address swingTrader,
  //     address swingTraderManager
  //   ) = poolFactory.getCoreContracts(pool);

  //   assertTrue(auction != address(0));
  //   assertTrue(auctionEscapeHatch != address(0));
  //   assertEq(impliedCollateralService, address(0));
  //   assertEq(liquidityExtension, address(0));
  //   assertEq(profitDistributor, address(0));
  //   assertEq(stabilizerNode, address(0));
  //   assertEq(swingTrader, address(0));
  //   assertEq(swingTraderManager, address(0));
  // }

  // function testDeployingStabilizer() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployStabilizer(pool, 10**18);

  //   vm.prank(admin);
  //   poolFactory.deployStabilizer(pool, 10**18);

  //   vm.prank(admin);
  //   vm.expectRevert("Stabilizer already deployed");
  //   poolFactory.deployStabilizer(pool, 10**18);

  //   (
  //     address auction,
  //     address auctionEscapeHatch,
  //     address impliedCollateralService,
  //     address liquidityExtension,
  //     address profitDistributor,
  //     address stabilizerNode,
  //     address swingTrader,
  //     address swingTraderManager
  //   ) = poolFactory.getCoreContracts(pool);

  //   assertEq(auction, address(0));
  //   assertEq(auctionEscapeHatch, address(0));
  //   assertEq(impliedCollateralService, address(0));
  //   assertEq(liquidityExtension, address(0));
  //   assertTrue(profitDistributor != address(0));
  //   assertTrue(stabilizerNode != address(0));
  //   assertEq(swingTrader, address(0));
  //   assertEq(swingTraderManager, address(0));
  // }

  // function testDeployingSwingTrader() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deploySwingTrader(pool);

  //   vm.prank(admin);
  //   poolFactory.deploySwingTrader(pool);

  //   vm.prank(admin);
  //   vm.expectRevert("SwingTrader already deployed");
  //   poolFactory.deploySwingTrader(pool);

  //   (
  //     address auction,
  //     address auctionEscapeHatch,
  //     address impliedCollateralService,
  //     address liquidityExtension,
  //     address profitDistributor,
  //     address stabilizerNode,
  //     address swingTrader,
  //     address swingTraderManager
  //   ) = poolFactory.getCoreContracts(pool);

  //   assertEq(auction, address(0));
  //   assertEq(auctionEscapeHatch, address(0));
  //   assertEq(impliedCollateralService, address(0));
  //   assertEq(liquidityExtension, address(0));
  //   assertEq(profitDistributor, address(0));
  //   assertEq(stabilizerNode, address(0));
  //   assertTrue(swingTrader != address(0));
  //   assertTrue(swingTraderManager != address(0));
  // }

  // function testDeployingImpliedCollateral() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployImpliedCollateral(pool);

  //   vm.prank(admin);
  //   poolFactory.deployImpliedCollateral(pool);

  //   vm.prank(admin);
  //   vm.expectRevert("ImpliedCollateral already deployed");
  //   poolFactory.deployImpliedCollateral(pool);

  //   (
  //     address auction,
  //     address auctionEscapeHatch,
  //     address impliedCollateralService,
  //     address liquidityExtension,
  //     address profitDistributor,
  //     address stabilizerNode,
  //     address swingTrader,
  //     address swingTraderManager
  //   ) = poolFactory.getCoreContracts(pool);

  //   assertEq(auction, address(0));
  //   assertEq(auctionEscapeHatch, address(0));
  //   assertTrue(impliedCollateralService != address(0));
  //   assertTrue(liquidityExtension != address(0));
  //   assertEq(profitDistributor, address(0));
  //   assertEq(stabilizerNode, address(0));
  //   assertEq(swingTrader, address(0));
  //   assertEq(swingTraderManager, address(0));
  // }

  // function testDeployingBonding() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployBonding(pool);

  //   vm.prank(admin);
  //   poolFactory.deployBonding(pool);

  //   vm.prank(admin);
  //   vm.expectRevert("Bonding already deployed");
  //   poolFactory.deployBonding(pool);

  //   (
  //     address bonding,
  //     address miningService,
  //     address vestedMine,
  //     address forfeitHandler,
  //     address linearMine,
  //     address reinvestor
  //   ) = poolFactory.getStakingContracts(pool);

  //   assertTrue(bonding != address(0));
  //   assertTrue(miningService != address(0));
  //   assertEq(vestedMine, address(0));
  //   assertEq(forfeitHandler, address(0));
  //   assertEq(linearMine, address(0));
  //   assertEq(reinvestor, address(0));
  // }

  // function testDeployingRewardMine() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployRewardMine(pool);

  //   vm.prank(admin);
  //   poolFactory.deployRewardMine(pool);

  //   vm.prank(admin);
  //   vm.expectRevert("RewardMine already deployed");
  //   poolFactory.deployRewardMine(pool);

  //   (
  //     address bonding,
  //     address miningService,
  //     address vestedMine,
  //     address forfeitHandler,
  //     address linearMine,
  //     address reinvestor
  //   ) = poolFactory.getStakingContracts(pool);

  //   assertEq(bonding, address(0));
  //   assertEq(miningService, address(0));
  //   assertTrue(vestedMine != address(0));
  //   assertTrue(linearMine != address(0));
  //   assertEq(forfeitHandler, address(0));
  //   assertEq(reinvestor, address(0));
  // }

  // function testDeployingStakingPeriphery() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployStakingPeriphery(pool);

  //   vm.prank(admin);
  //   poolFactory.deployStakingPeriphery(pool);

  //   vm.prank(admin);
  //   vm.expectRevert("StakingPeriphery already deployed");
  //   poolFactory.deployStakingPeriphery(pool);

  //   (
  //     address bonding,
  //     address miningService,
  //     address vestedMine,
  //     address forfeitHandler,
  //     address linearMine,
  //     address reinvestor
  //   ) = poolFactory.getStakingContracts(pool);

  //   assertEq(bonding, address(0));
  //   assertEq(miningService, address(0));
  //   assertEq(vestedMine, address(0));
  //   assertEq(linearMine, address(0));
  //   assertTrue(forfeitHandler != address(0));
  //   assertTrue(reinvestor != address(0));
  // }

  // function testDeployingRewardSystem() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployRewardSystem(pool);

  //   vm.prank(admin);
  //   poolFactory.deployRewardSystem(pool);

  //   vm.prank(admin);
  //   vm.expectRevert("RewardSystem already deployed");
  //   poolFactory.deployRewardSystem(pool);

  //   (
  //     address vestingDistributor,
  //     address linearDistributor,
  //     address rewardOverflow,
  //     address rewardThrottle
  //   ) = poolFactory.getRewardSystemContracts(pool);

  //   assertTrue(vestingDistributor != address(0));
  //   assertTrue(linearDistributor != address(0));
  //   assertTrue(rewardOverflow != address(0));
  //   assertTrue(rewardThrottle != address(0));
  // }

  // function testDeployingDataFeed() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployDataFeed(pool, (10**18)*2);

  //   vm.prank(admin);
  //   poolFactory.deployDataFeed(pool, (10**18)*2);

  //   vm.prank(admin);
  //   vm.expectRevert("DataFeed already deployed");
  //   poolFactory.deployDataFeed(pool, (10**18)*2);

  //   (
  //     address dataLab,
  //     address dexHandler,
  //     address transferVerifier,
  //     address keeper,
  //     address dualMA
  //   ) = poolFactory.getPeripheryContracts(pool);

  //   assertTrue(dataLab != address(0));
  //   assertTrue(dualMA != address(0));
  //   assertEq(dexHandler, address(0));
  //   assertEq(transferVerifier, address(0));
  //   assertEq(keeper, address(0));
  // }

  // function testDeployingUniV2DexHandler() public {
  //   address pool = nextAddress();
  //   address router = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployUniV2DexHandler(pool, router);

  //   vm.prank(admin);
  //   poolFactory.deployUniV2DexHandler(pool, router);

  //   vm.prank(admin);
  //   vm.expectRevert("DexHandler already deployed");
  //   poolFactory.deployUniV2DexHandler(pool, router);

  //   (
  //     address dataLab,
  //     address dexHandler,
  //     address transferVerifier,
  //     address keeper,
  //     address dualMA
  //   ) = poolFactory.getPeripheryContracts(pool);

  //   assertEq(dataLab, address(0));
  //   assertEq(dualMA, address(0));
  //   assertTrue(dexHandler != address(0));
  //   assertEq(transferVerifier, address(0));
  //   assertEq(keeper, address(0));
  // }

  // function testDeployingTransferVerfier() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployTransferVerifier(pool);

  //   vm.prank(admin);
  //   poolFactory.deployTransferVerifier(pool);

  //   vm.prank(admin);
  //   vm.expectRevert("TransferVerfier already deployed");
  //   poolFactory.deployTransferVerifier(pool);

  //   (
  //     address dataLab,
  //     address dexHandler,
  //     address transferVerifier,
  //     address keeper,
  //     address dualMA
  //   ) = poolFactory.getPeripheryContracts(pool);

  //   assertEq(dataLab, address(0));
  //   assertEq(dualMA, address(0));
  //   assertEq(dexHandler, address(0));
  //   assertTrue(transferVerifier != address(0));
  //   assertEq(keeper, address(0));
  // }

  // function testDeployingUniV2Keeper() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.deployUniV2Keeper(pool);

  //   vm.prank(admin);
  //   poolFactory.deployUniV2Keeper(pool);

  //   vm.prank(admin);
  //   vm.expectRevert("Keeper already deployed");
  //   poolFactory.deployUniV2Keeper(pool);

  //   (
  //     address dataLab,
  //     address dexHandler,
  //     address transferVerifier,
  //     address keeper,
  //     address dualMA
  //   ) = poolFactory.getPeripheryContracts(pool);

  //   assertEq(dataLab, address(0));
  //   assertEq(dualMA, address(0));
  //   assertEq(dexHandler, address(0));
  //   assertEq(transferVerifier, address(0));
  //   assertTrue(keeper != address(0));
  // }

  // function testSetupFailsForRandomPool(address randomPool) public {
  //   address pool = nextAddress();
  //   vm.assume(randomPool != pool);
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(admin);
  //   vm.expectRevert("Unknown pool");
  //   poolFactory.setupUniv2StabilizedPool(randomPool);
  // }

  // function testSetupFailsWhenNotInitialized() public {
  //   address pool = nextAddress();
  //   address randomUser = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  // }

  // TODO resurrect some of these tests and explicitly test setupUniv2StabilizedPool Mon 17 Oct 2022 23:02:12 BST
  // TODO also test changing the updater Mon 17 Oct 2022 23:03:03 BST

  // function testOnlyAllowsSetupWhenFullyDeployed() public {
  //   ERC20 lpToken = new ERC20("DAI Stablecoin", "DAI");
  //   address pool = address(lpToken);
  //   address randomUser = nextAddress();
  //   address router = nextAddress();
  //   string memory name = "My Test Pool";

  //   vm.prank(admin);
  //   poolFactory.initializeStabilizedPool(
  //     pool,
  //     name,
  //     address(rewardToken)
  //   );

  //   vm.startPrank(admin);

  //   vm.expectRevert("Auction not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployAuction(pool, 10**18);

  //   vm.expectRevert("ImpColSvc not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployImpliedCollateral(pool);

  //   vm.expectRevert("StabilizerNode not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployStabilizer(pool, 10**18);

  //   vm.expectRevert("SwingTrader not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deploySwingTrader(pool);

  //   vm.expectRevert("Bonding not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployBonding(pool);

  //   vm.expectRevert("VestedMine not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployRewardMine(pool);

  //   vm.expectRevert("ForfeitHandler not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployStakingPeriphery(pool);

  //   vm.expectRevert("VestingDist not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployRewardSystem(pool);

  //   vm.expectRevert("DataLab not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployDataFeed(pool, (10**18)*2);

  //   vm.expectRevert("DexHandler not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployUniV2DexHandler(pool, router);

  //   vm.expectRevert("TransferVerfier not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployTransferVerifier(pool);

  //   vm.expectRevert("Keeper not deployed");
  //   poolFactory.setupUniv2StabilizedPool(pool);
  //   poolFactory.deployUniV2Keeper(pool);

  //   poolFactory.setupUniv2StabilizedPool(pool);

  //   vm.stopPrank();
  // }

  // function testSettingInitialAdmin(address randomUser, address newAdmin) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   vm.assume(newAdmin != address(0));

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setInitialAdmin(newAdmin);

  //   vm.prank(admin);
  //   poolFactory.setInitialAdmin(newAdmin);
  // }

  function testSettingTimekeeper(address randomUser, address newTimekeeper)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(
      newTimekeeper != address(0) &&
        newTimekeeper != address(timekeeper) &&
        newTimekeeper != timelock
    );

    assertEq(poolFactory.timekeeper(), address(timekeeper));

    // Timekeeper starts off with mint privs
    vm.prank(address(timekeeper));
    malt.mint(address(randomUser), 10**18);

    // newTimekeeper does not
    vm.prank(newTimekeeper);
    vm.expectRevert("Must have monetary minter role");
    malt.mint(address(randomUser), 10**18);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolFactory.setTimekeeper(newTimekeeper);

    vm.prank(admin);
    poolFactory.setTimekeeper(newTimekeeper);

    assertEq(poolFactory.timekeeper(), newTimekeeper);

    // Now timekeeper cannot mint
    vm.prank(address(timekeeper));
    vm.expectRevert("Must have monetary minter role");
    malt.mint(address(randomUser), 10**18);


  // function testSetTreasury(address randomUser, address payable newTreasury) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   vm.assume(newTreasury != address(0) && newTreasury != treasury);

  //   assertEq(poolFactory.treasury(), treasury);

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setTreasury(newTreasury);

  //   vm.prank(admin);
  //   poolFactory.setTreasury(newTreasury);

  //   assertEq(poolFactory.treasury(), newTreasury);
  // }

  // function testSetKeeperRegister(address randomUser, address payable newRegistry) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   vm.assume(newRegistry != address(0) && newRegistry != keeperRegistry);

  //   assertEq(poolFactory.keeperRegistry(), keeperRegistry);

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setKeeperRegistry(newRegistry);

  //   vm.prank(admin);
  //   poolFactory.setKeeperRegistry(newRegistry);

  //   assertEq(poolFactory.keeperRegistry(), newRegistry);
  // }

  // function testSetGlobalIC(address randomUser, address newGlobalIC) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   vm.assume(newGlobalIC != address(0) && newGlobalIC != address(globalIC));

  //   assertEq(address(poolFactory.globalIC()), address(globalIC));

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setGlobalIC(newGlobalIC);

  //   vm.prank(admin);
  //   poolFactory.setGlobalIC(newGlobalIC);

  //   assertEq(address(poolFactory.globalIC()), newGlobalIC);
  // }

  // function testSetAuctionLength(address randomUser, uint256 newLength) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   vm.assume(newLength != 0);

  //   assertEq(poolFactory.auctionLength(), 600); // the default value

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setAuctionLength(newLength);

  //   vm.prank(admin);
  //   poolFactory.setAuctionLength(newLength);

  //   assertEq(poolFactory.auctionLength(), newLength);
  // }

  // function testSetLowerThresholdBps(address randomUser, uint256 newThreshold) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   newThreshold = bound(newThreshold, 1, 9999);

  //   assertEq(poolFactory.lowerThresholdBps(), 200); // the default value

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setLowerThresholdBps(newThreshold);

  //   vm.prank(admin);
  //   poolFactory.setLowerThresholdBps(newThreshold);

  //   assertEq(poolFactory.lowerThresholdBps(), newThreshold);
  // }

  // function testSetUpperThresholdBps(address randomUser, uint256 newThreshold) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   newThreshold = bound(newThreshold, 1, 9999);

  //   assertEq(poolFactory.upperThresholdBps(), 200); // the default value

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setUpperThresholdBps(newThreshold);

  //   vm.prank(admin);
  //   poolFactory.setUpperThresholdBps(newThreshold);

  //   assertEq(poolFactory.upperThresholdBps(), newThreshold);
  // }

  // function testSetLookbackAbove(address randomUser, uint256 newLookback) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   vm.assume(newLookback >= 30);

  //   assertEq(poolFactory.lookbackAbove(), 30); // the default value

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setLookbackAbove(newLookback);

  //   vm.prank(admin);
  //   poolFactory.setLookbackAbove(newLookback);

  //   assertEq(poolFactory.lookbackAbove(), newLookback);
  // }

  // function testSetLookbackBelow(address randomUser, uint256 newLookback) public {
  //   vm.assume(randomUser != admin && randomUser != address(0) && randomUser != timelock);
  //   vm.assume(newLookback >= 30);

  //   assertEq(poolFactory.lookbackBelow(), 60*5); // the default value

  //   vm.prank(randomUser);
  //   vm.expectRevert("Must have admin role");
  //   poolFactory.setLookbackBelow(newLookback);

  //   vm.prank(admin);
  //   poolFactory.setLookbackBelow(newLookback);

  //   assertEq(poolFactory.lookbackBelow(), newLookback);
  // }
    // But newTimekeeper can
    vm.prank(newTimekeeper);
    malt.mint(address(randomUser), 10**18);
  }
}

contract DeployedPoolStabilizedPoolFactoryTest is DeployedStabilizedPool {
  using stdStorage for StdStorage;

  function testAllContractsExist() public {
    (
      address auction,
      address auctionEscapeHatch,
      address impliedCollateralService,
      address liquidityExtension,
      address profitDistributor,
      address stabilizerNode,
      address swingTrader,
      address swingTraderManager
    ) = poolFactory.getCoreContracts(pool);

    assertTrue(auction != address(0));
    assertTrue(auctionEscapeHatch != address(0));
    assertTrue(impliedCollateralService != address(0));
    assertTrue(liquidityExtension != address(0));
    assertTrue(profitDistributor != address(0));
    assertTrue(stabilizerNode != address(0));
    assertTrue(swingTrader != address(0));
    assertTrue(swingTraderManager != address(0));

    (
      address vestingDistributor,
      address linearDistributor,
      address rewardOverflow,
      address rewardThrottle
    ) = poolFactory.getRewardSystemContracts(pool);

    assertTrue(vestingDistributor != address(0));
    assertTrue(linearDistributor != address(0));
    assertTrue(rewardOverflow != address(0));
    assertTrue(rewardThrottle != address(0));

    (
      address bonding,
      address miningService,
      address vestedMine,
      address forfeitHandler,
      address linearMine,
      address reinvestor
    ) = poolFactory.getStakingContracts(pool);

    assertTrue(bonding != address(0));
    assertTrue(miningService != address(0));
    assertTrue(vestedMine != address(0));
    assertTrue(forfeitHandler != address(0));
    assertTrue(linearMine != address(0));
    assertTrue(reinvestor != address(0));

    (
      address dataLab,
      address dexHandler,
      address transferVerifier,
      address keeper,
      address dualMA
    ) = poolFactory.getPeripheryContracts(pool);

    assertTrue(dataLab != address(0));
    assertTrue(dualMA != address(0));
    assertTrue(dexHandler != address(0));
    assertTrue(transferVerifier != address(0));
    assertTrue(keeper != address(0));
  }

  function testFailsToUpdateTimekeeperForUnknownPool(address randomPool)
    public
  {
    vm.assume(randomPool != address(0) && randomPool != pool);
    vm.expectRevert("Unknown pool");
    poolUpdater.updateTimekeeper(randomPool, address(0x3023));
  }

  function testUpdateDAO(address randomUser, address newDAO) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newDAO != address(0) && newDAO != dao);

    (, , , , address profitDistributor, , , ) = poolFactory.getCoreContracts(
      pool
    );

    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);

    // Assert all contracts has pointer to original DAO contract
    assertEq(address(profitDist.dao()), dao);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateDAO(pool, newDAO);

    vm.prank(admin);
    poolUpdater.updateDAO(pool, newDAO);

    // Assert pointers have now changed
    assertEq(address(profitDist.dao()), newDAO);
  }

  function testUpdateTimekeeper(address randomUser, address newTimekeeper)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newTimekeeper != address(0));

    (address bonding, , , , , ) = poolFactory.getStakingContracts(pool);
    (, , , address rewardThrottle) = poolFactory.getRewardSystemContracts(pool);
    (, , , address keeper, ) = poolFactory.getPeripheryContracts(pool);

    Bonding bondingContract = Bonding(bonding);
    RewardThrottle throttle = RewardThrottle(rewardThrottle);
    UniV2PoolKeeper keeperContract = UniV2PoolKeeper(keeper);

    // Assert all contracts have pointer to original Timekeeper contract
    assertEq(address(bondingContract.timekeeper()), address(timekeeper));
    assertEq(address(throttle.timekeeper()), address(timekeeper));
    assertEq(address(keeperContract.timekeeper()), address(timekeeper));

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateTimekeeper(pool, newTimekeeper);

    vm.prank(admin);
    poolUpdater.updateTimekeeper(pool, newTimekeeper);

    // Assert pointers have now changed
    assertEq(address(bondingContract.timekeeper()), newTimekeeper);
    assertEq(address(throttle.timekeeper()), newTimekeeper);
    assertEq(address(keeperContract.timekeeper()), newTimekeeper);
  }

  function testFailsToUpdateTreasuryForUnknownPool(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateTreasury(randomPool, payable(address(0x3023)));
  }

  function testUpdateTreasury(address randomUser, address payable newTreasury)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newTreasury != address(0));

    (, , , , address profitDistributor, , , ) = poolFactory.getCoreContracts(
      pool
    );
    (, , , address forfeitHandler, , address reinvestor) = poolFactory
      .getStakingContracts(pool);

    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);
    ForfeitHandler forfeitContract = ForfeitHandler(forfeitHandler);
    RewardReinvestor reinvest = RewardReinvestor(reinvestor);

    // Assert all contracts have pointer to original contract
    assertEq(address(profitDist.treasury()), treasury);
    assertEq(address(forfeitContract.treasury()), treasury);
    assertEq(address(reinvest.treasury()), treasury);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateTreasury(pool, newTreasury);

    vm.prank(admin);
    poolUpdater.updateTreasury(pool, newTreasury);

    // Assert pointers have now changed
    assertEq(address(profitDist.treasury()), newTreasury);
    assertEq(address(forfeitContract.treasury()), newTreasury);
    assertEq(address(reinvest.treasury()), newTreasury);
  }

  function testFailsToUpdateGlobalICForUnknownPool(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateGlobalIC(randomPool, address(0x3023));
  }

  function testUpdateGlobalIC(address randomUser, address newGlobalIC) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newGlobalIC != address(0));

    (
      ,
      ,
      address impliedCollateralService,
      ,
      address profitDistributor,
      ,
      ,

    ) = poolFactory.getCoreContracts(pool);
    (address dataLab, , , , ) = poolFactory.getPeripheryContracts(pool);

    ImpliedCollateralService impCol = ImpliedCollateralService(
      impliedCollateralService
    );
    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);
    MaltDataLab maltDataLab = MaltDataLab(dataLab);

    // Assert all contracts have pointer to original contract
    assertEq(address(impCol.globalIC()), address(globalIC));
    assertEq(address(profitDist.globalIC()), address(globalIC));
    assertEq(address(maltDataLab.globalIC()), address(globalIC));

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateGlobalIC(pool, newGlobalIC);

    vm.prank(admin);
    poolUpdater.updateGlobalIC(pool, newGlobalIC);

    // Assert pointers have now changed
    assertEq(address(impCol.globalIC()), newGlobalIC);
    assertEq(address(profitDist.globalIC()), newGlobalIC);
    assertEq(address(maltDataLab.globalIC()), newGlobalIC);
  }

  function testFailsToUpdateAuctionForUnknownPool(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateAuction(randomPool, address(0x3023));
  }

  function testUpdateAuction(address randomUser, address newAuction) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newAuction != address(0));

    (
      address auction,
      address auctionEscapeHatch,
      address impliedCollateralService,
      address liquidityExtension,
      address profitDistributor,
      address stabilizerNode,
      ,

    ) = poolFactory.getCoreContracts(pool);

    AuctionEscapeHatch escape = AuctionEscapeHatch(auctionEscapeHatch);
    ImpliedCollateralService impCol = ImpliedCollateralService(
      impliedCollateralService
    );
    LiquidityExtension liqExt = LiquidityExtension(liquidityExtension);
    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);
    StabilizerNode stabNode = StabilizerNode(stabilizerNode);

    // Assert all contracts have pointer to original contract
    assertEq(address(escape.auction()), auction);
    assertEq(address(impCol.auction()), auction);
    assertEq(address(liqExt.auction()), auction);
    assertEq(address(profitDist.auction()), auction);
    assertEq(address(stabNode.auction()), auction);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateAuction(pool, newAuction);

    vm.prank(admin);
    poolUpdater.updateAuction(pool, newAuction);

    // Assert pointers have now changed
    assertEq(address(escape.auction()), newAuction);
    assertEq(address(impCol.auction()), newAuction);
    assertEq(address(liqExt.auction()), newAuction);
    assertEq(address(profitDist.auction()), newAuction);
    assertEq(address(stabNode.auction()), newAuction);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.core.auction, newAuction);
  }

  function testFailsToUpdateAuctionEscapeForUnknownPool(address randomPool)
    public
  {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateAuctionEscapeHatch(randomPool, address(0x3023));
  }

  function testUpdateAuctionEscape(address randomUser, address newAuctionEscape)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    assumeNoMaltContracts(newAuctionEscape);

    (
      address auction,
      address auctionEscapeHatch,
      address impliedCollateralService,
      address liquidityExtension,
      address profitDistributor,
      address stabilizerNode,
      ,

    ) = poolFactory.getCoreContracts(pool);

    (, address dexHandler, , , ) = poolFactory.getPeripheryContracts(pool);

    Auction auctionContract = Auction(auction);

    // Assert all contracts have pointer to original contract
    assertEq(address(auctionContract.amender()), auctionEscapeHatch);

    bytes32 amenderRole = keccak256("AUCTION_AMENDER_ROLE");
    bytes32 minterRole = keccak256("MONETARY_MINTER_ROLE");
    bytes32 sellerRole = keccak256("SELLER_ROLE");
    assertHasMaltRole(auction, amenderRole, auctionEscapeHatch);
    assertNotHasMaltRole(auction, amenderRole, newAuctionEscape);
    assertHasMaltRole(address(malt), minterRole, auctionEscapeHatch);
    assertNotHasMaltRole(address(malt), minterRole, newAuctionEscape);
    assertHasMaltRole(dexHandler, sellerRole, auctionEscapeHatch);
    assertNotHasMaltRole(dexHandler, sellerRole, newAuctionEscape);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateAuctionEscapeHatch(pool, newAuctionEscape);

    vm.prank(admin);
    poolUpdater.updateAuctionEscapeHatch(pool, newAuctionEscape);

    assertHasMaltRole(auction, amenderRole, newAuctionEscape);
    assertNotHasMaltRole(auction, amenderRole, auctionEscapeHatch);
    assertHasMaltRole(address(malt), minterRole, newAuctionEscape);
    assertNotHasMaltRole(address(malt), minterRole, auctionEscapeHatch);
    assertHasMaltRole(dexHandler, sellerRole, newAuctionEscape);
    assertNotHasMaltRole(dexHandler, sellerRole, auctionEscapeHatch);

    // Assert pointers have now changed
    assertEq(address(auctionContract.amender()), newAuctionEscape);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.core.auctionEscapeHatch, newAuctionEscape);
  }

  function testFailsToUpdateImpliedColForUnknownPool(address randomPool)
    public
  {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateAuction(randomPool, address(0x3023));
  }

  function testUpdateImpliedCol(address randomUser, address newImpCol) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newImpCol != address(0));

    (
      address auction,
      ,
      address impliedCollateralService,
      ,
      address profitDistributor,
      address stabilizerNode,
      ,

    ) = poolFactory.getCoreContracts(pool);

    (address dataLab, , , , ) = poolFactory.getPeripheryContracts(pool);

    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);
    StabilizerNode stabNode = StabilizerNode(stabilizerNode);
    MaltDataLab maltDataLab = MaltDataLab(dataLab);

    // Assert all contracts have pointer to original contract
    assertEq(
      address(profitDist.impliedCollateralService()),
      impliedCollateralService
    );
    assertEq(
      address(stabNode.impliedCollateralService()),
      impliedCollateralService
    );
    assertEq(
      address(maltDataLab.impliedCollateralService()),
      impliedCollateralService
    );

    address updater = globalIC.poolUpdatersLookup(pool);
    assertEq(updater, impliedCollateralService);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateImpliedCollateralService(pool, newImpCol);

    vm.prank(admin);
    poolUpdater.updateImpliedCollateralService(pool, newImpCol);

    // Assert pointers have now changed
    assertEq(address(profitDist.impliedCollateralService()), newImpCol);
    assertEq(address(stabNode.impliedCollateralService()), newImpCol);
    assertEq(address(maltDataLab.impliedCollateralService()), newImpCol);

    updater = globalIC.poolUpdatersLookup(pool);
    assertEq(updater, newImpCol);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.core.impliedCollateralService, newImpCol);
  }

  function testFailsToUpdateLiquidityExtension(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateLiquidityExtension(randomPool, address(0x3023));
  }

  function testUpdateLiquidityExtension(address randomUser, address newLE)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    assumeNoMaltContracts(newLE);

    (
      address auction,
      ,
      address impliedCollateralService,
      address liquidityExtension,
      address profitDistributor,
      ,
      ,

    ) = poolFactory.getCoreContracts(pool);

    Auction auctionContract = Auction(auction);
    ImpliedCollateralService impCol = ImpliedCollateralService(
      impliedCollateralService
    );
    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);

    // Assert all contracts have pointer to original contract
    assertEq(address(auctionContract.liquidityExtension()), liquidityExtension);
    assertEq(address(impCol.liquidityExtension()), liquidityExtension);
    assertEq(address(profitDist.liquidityExtension()), liquidityExtension);

    bytes32 burnerRole = keccak256("MONETARY_BURNER_ROLE");
    assertHasMaltRole(address(malt), burnerRole, liquidityExtension);
    assertNotHasMaltRole(address(malt), burnerRole, newLE);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateLiquidityExtension(pool, newLE);

    vm.prank(admin);
    poolUpdater.updateLiquidityExtension(pool, newLE);

    // Assert pointers have now changed
    assertEq(address(auctionContract.liquidityExtension()), newLE);
    assertEq(address(impCol.liquidityExtension()), newLE);
    assertEq(address(profitDist.liquidityExtension()), newLE);

    assertHasMaltRole(address(malt), burnerRole, newLE);
    assertNotHasMaltRole(address(malt), burnerRole, liquidityExtension);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.core.liquidityExtension, newLE);
  }

  function testFailsToUpdateProfitDistributor(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateProfitDistributor(randomPool, address(0x3023));
  }

  function testUpdateProfitDistributor(
    address randomUser,
    address newProfitDist
  ) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newProfitDist != address(0));

    (
      ,
      ,
      ,
      ,
      address profitDistributor,
      address stabilizerNode,
      address swingTrader,

    ) = poolFactory.getCoreContracts(pool);

    (, , address rewardOverflow, ) = poolFactory.getRewardSystemContracts(pool);

    StabilizerNode stabNode = StabilizerNode(stabilizerNode);
    SwingTrader swingTrade = SwingTrader(swingTrader);
    RewardOverflowPool overflow = RewardOverflowPool(rewardOverflow);

    // Assert all contracts have pointer to original contract
    assertEq(address(stabNode.profitDistributor()), profitDistributor);
    assertEq(address(swingTrade.profitDistributor()), profitDistributor);
    assertEq(address(overflow.profitDistributor()), profitDistributor);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateProfitDistributor(pool, newProfitDist);

    vm.prank(admin);
    poolUpdater.updateProfitDistributor(pool, newProfitDist);

    // Assert pointers have now changed
    assertEq(address(stabNode.profitDistributor()), newProfitDist);
    assertEq(address(swingTrade.profitDistributor()), newProfitDist);
    assertEq(address(overflow.profitDistributor()), newProfitDist);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.core.profitDistributor, newProfitDist);
  }

  function testFailsToUpdateStabilizerNode(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateStabilizerNode(randomPool, address(0x3023));
  }

  function testUpdateStabilizerNode(address randomUser, address newStabNode)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    assumeNoMaltContracts(newStabNode);

    (
      address auction,
      ,
      address impliedCollateralService,
      ,
      ,
      address stabilizerNode,
      address swingTrader,
      address swingTraderManager
    ) = poolFactory.getCoreContracts(pool);

    (, , address rewardOverflow, ) = poolFactory.getRewardSystemContracts(pool);
    (, address dexHandler, , , ) = poolFactory.getPeripheryContracts(pool);

    Auction auctionContract = Auction(auction);
    ImpliedCollateralService impCol = ImpliedCollateralService(
      impliedCollateralService
    );
    SwingTraderManager stManager = SwingTraderManager(swingTraderManager);

    // Assert all contracts have pointer to original contract
    assertEq(address(auctionContract.stabilizerNode()), stabilizerNode);
    assertEq(address(impCol.stabilizerNode()), stabilizerNode);
    assertEq(address(stManager.stabilizerNode()), stabilizerNode);

    bytes32 minterRole = keccak256("MONETARY_MINTER_ROLE");
    bytes32 sellerRole = keccak256("SELLER_ROLE");
    assertHasMaltRole(address(malt), minterRole, stabilizerNode);
    assertNotHasMaltRole(address(malt), minterRole, newStabNode);
    assertHasMaltRole(dexHandler, sellerRole, stabilizerNode);
    assertNotHasMaltRole(dexHandler, sellerRole, newStabNode);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateStabilizerNode(pool, newStabNode);

    vm.prank(admin);
    poolUpdater.updateStabilizerNode(pool, newStabNode);

    // Assert pointers have now changed
    assertEq(address(auctionContract.stabilizerNode()), newStabNode);
    assertEq(address(impCol.stabilizerNode()), newStabNode);
    assertEq(address(stManager.stabilizerNode()), newStabNode);

    assertHasMaltRole(address(malt), minterRole, newStabNode);
    assertNotHasMaltRole(address(malt), minterRole, stabilizerNode);
    assertHasMaltRole(dexHandler, sellerRole, newStabNode);
    assertNotHasMaltRole(dexHandler, sellerRole, stabilizerNode);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.core.stabilizerNode, newStabNode);
  }

  function testFailsToUpdateSwingTrader(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateSwingTrader(randomPool, address(0x3023));
  }

  function testUpdateSwingTrader(address randomUser, address newST) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    assumeNoMaltContracts(newST);

    (
      ,
      ,
      ,
      address liquidityExtension,
      address profitDistributor,
      ,
      address swingTrader,

    ) = poolFactory.getCoreContracts(pool);

    (, address dexHandler, , , ) = poolFactory.getPeripheryContracts(pool);

    LiquidityExtension liqExt = LiquidityExtension(liquidityExtension);
    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);

    // Assert all contracts have pointer to original contract
    assertEq(address(liqExt.swingTrader()), swingTrader);
    assertEq(address(profitDist.swingTrader()), swingTrader);

    bytes32 buyerRole = keccak256("BUYER_ROLE");
    bytes32 sellerRole = keccak256("SELLER_ROLE");
    assertHasMaltRole(dexHandler, buyerRole, swingTrader);
    assertNotHasMaltRole(dexHandler, buyerRole, newST);
    assertHasMaltRole(dexHandler, sellerRole, swingTrader);
    assertNotHasMaltRole(dexHandler, sellerRole, newST);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateSwingTrader(pool, newST);

    vm.prank(admin);
    poolUpdater.updateSwingTrader(pool, newST);

    // Assert pointers have now changed
    assertEq(address(liqExt.swingTrader()), newST);
    assertEq(address(profitDist.swingTrader()), newST);

    assertHasMaltRole(dexHandler, buyerRole, newST);
    assertNotHasMaltRole(dexHandler, buyerRole, swingTrader);
    assertHasMaltRole(dexHandler, sellerRole, newST);
    assertNotHasMaltRole(dexHandler, sellerRole, swingTrader);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.core.swingTrader, newST);
  }

  function testFailsToUpdateSwingTraderManager(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateSwingTraderManager(randomPool, address(0x3023));
  }

  function testUpdateSwingTraderManager(
    address randomUser,
    address newStManager
  ) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    assumeNoMaltContracts(newStManager);

    (
      ,
      ,
      address impliedCollateralService,
      ,
      ,
      address stabilizerNode,
      address swingTrader,
      address swingTraderManager
    ) = poolFactory.getCoreContracts(pool);

    (, , address rewardOverflow, ) = poolFactory.getRewardSystemContracts(pool);

    (address dataLab, , , , ) = poolFactory.getPeripheryContracts(pool);

    ImpliedCollateralService impCol = ImpliedCollateralService(
      impliedCollateralService
    );
    StabilizerNode stabNode = StabilizerNode(stabilizerNode);
    SwingTrader swingTrade = SwingTrader(swingTrader);
    RewardOverflowPool overflow = RewardOverflowPool(rewardOverflow);
    MaltDataLab maltDataLab = MaltDataLab(dataLab);

    // Assert all contracts have pointer to original contract
    assertEq(address(impCol.swingTraderManager()), swingTraderManager);
    assertEq(address(maltDataLab.swingTraderManager()), swingTraderManager);

    bytes32 managerRole = keccak256("MANAGER_ROLE");
    assertHasMaltRole(swingTrader, managerRole, swingTraderManager);
    assertHasMaltRole(rewardOverflow, managerRole, swingTraderManager);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateSwingTraderManager(pool, newStManager);

    vm.prank(admin);
    poolUpdater.updateSwingTraderManager(pool, newStManager);

    // Assert pointers have now changed
    assertEq(address(impCol.swingTraderManager()), newStManager);
    assertEq(address(maltDataLab.swingTraderManager()), newStManager);
    assertHasMaltRole(swingTrader, managerRole, newStManager);
    assertHasMaltRole(rewardOverflow, managerRole, newStManager);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.core.swingTraderManager, newStManager);
  }

  function testFailsToUpdateVestedMine(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateVestedMine(randomPool, address(0x3023));
  }

  function testUpdateVestedMine(address randomUser, address newVestedMine)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );

    (, , address initialVestedMine, , , ) = poolFactory.getStakingContracts(
      pool
    );

    vm.assume(
      newVestedMine != address(0) && newVestedMine != initialVestedMine
    );

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateVestedMine(pool, newVestedMine);

    vm.prank(admin);
    poolUpdater.updateVestedMine(pool, newVestedMine);

    (, , address vestedMine, , , ) = poolFactory.getStakingContracts(pool);

    assertTrue(initialVestedMine != vestedMine);
    assertEq(vestedMine, newVestedMine);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.staking.vestedMine, newVestedMine);
  }

  function testFailsToUpdateForfeitHandler(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateForfeitHandler(randomPool, address(0x3023));
  }

  function testUpdateForfeitHandler(
    address randomUser,
    address newForfeitHandler
  ) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newForfeitHandler != address(0));

    (, , , address forfeitHandler, , ) = poolFactory.getStakingContracts(pool);

    (address vestingDistributor, address linearDistributor, , ) = poolFactory
      .getRewardSystemContracts(pool);

    VestingDistributor vestingDist = VestingDistributor(vestingDistributor);
    LinearDistributor linearDist = LinearDistributor(linearDistributor);

    // Assert all contracts have pointer to original contract
    assertEq(address(vestingDist.forfeitor()), forfeitHandler);
    assertEq(address(linearDist.forfeitor()), forfeitHandler);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateForfeitHandler(pool, newForfeitHandler);

    vm.prank(admin);
    poolUpdater.updateForfeitHandler(pool, newForfeitHandler);

    // Assert pointers have now changed
    assertEq(address(vestingDist.forfeitor()), newForfeitHandler);
    assertEq(address(linearDist.forfeitor()), newForfeitHandler);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.staking.forfeitHandler, newForfeitHandler);
  }

  function testFailsToUpdateBonding(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateBonding(randomPool, address(0x3023));
  }

  function testUpdateBonding(address randomUser, address newBonding) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    assumeNoMaltContracts(newBonding);

    (
      address bonding,
      address miningService,
      ,
      ,
      ,
      address reinvestor
    ) = poolFactory.getStakingContracts(pool);

    (, , , address rewardThrottle) = poolFactory.getRewardSystemContracts(pool);

    (, address dexHandler, , , ) = poolFactory.getPeripheryContracts(pool);

    MiningService miningSvc = MiningService(miningService);
    RewardReinvestor rewardReinvestor = RewardReinvestor(reinvestor);
    RewardThrottle throttle = RewardThrottle(rewardThrottle);

    bytes32 removerRole = keccak256("LIQUIDITY_REMOVER_ROLE");
    assertHasMaltRole(dexHandler, removerRole, bonding);
    assertNotHasMaltRole(dexHandler, removerRole, newBonding);

    // Assert all contracts have pointer to original contract
    assertEq(address(miningSvc.bonding()), bonding);
    assertEq(address(rewardReinvestor.bonding()), bonding);
    assertEq(address(throttle.bonding()), bonding);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateBonding(pool, newBonding);

    vm.prank(admin);
    poolUpdater.updateBonding(pool, newBonding);

    // Assert pointers have now changed
    assertEq(address(miningSvc.bonding()), newBonding);
    assertEq(address(rewardReinvestor.bonding()), newBonding);
    assertEq(address(throttle.bonding()), newBonding);

    assertHasMaltRole(dexHandler, removerRole, newBonding);
    assertNotHasMaltRole(dexHandler, removerRole, bonding);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.staking.bonding, newBonding);
  }

  function testFailsToUpdateMiningService(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateMiningService(randomPool, address(0x3023));
  }

  function testUpdateMiningService(address randomUser, address newMiningService)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newMiningService != address(0));

    (
      address bonding,
      address miningService,
      address vestedMine,
      ,
      address linearMine,
      address reinvestor
    ) = poolFactory.getStakingContracts(pool);

    Bonding bondingContract = Bonding(bonding);
    ERC20VestedMine vested = ERC20VestedMine(vestedMine);
    RewardMineBase base = RewardMineBase(linearMine);
    RewardReinvestor reinvest = RewardReinvestor(reinvestor);

    // Assert all contracts have pointer to original contract
    assertEq(address(bondingContract.miningService()), miningService);
    assertEq(address(vested.miningService()), miningService);
    assertEq(address(base.miningService()), miningService);
    assertEq(address(reinvest.miningService()), miningService);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateMiningService(pool, newMiningService);

    vm.prank(admin);
    poolUpdater.updateMiningService(pool, newMiningService);

    // Assert pointers have now changed
    assertEq(address(bondingContract.miningService()), newMiningService);
    assertEq(address(vested.miningService()), newMiningService);
    assertEq(address(base.miningService()), newMiningService);
    assertEq(address(reinvest.miningService()), newMiningService);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.staking.miningService, newMiningService);
  }

  function testFailsToUpdateLinearMine(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateLinearMine(randomPool, address(0x3023));
  }

  function testUpdateLinearMine(address randomUser, address newLinearMine)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newLinearMine != address(0));

    (, , address initialLinearMine, , , ) = poolFactory.getStakingContracts(
      pool
    );
    vm.assume(newLinearMine != initialLinearMine);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateLinearMine(pool, newLinearMine);

    vm.prank(admin);
    poolUpdater.updateLinearMine(pool, newLinearMine);

    (, , , , address linearMine, ) = poolFactory.getStakingContracts(pool);

    assertTrue(initialLinearMine != linearMine);
    assertEq(linearMine, newLinearMine);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.staking.linearMine, newLinearMine);
  }

  function testFailsToUpdateReinvestor(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateReinvestor(randomPool, address(0x3023));
  }

  function testUpdateReinvestor(address randomUser, address newReinvestor)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    assumeNoMaltContracts(newReinvestor);

    (
      ,
      ,
      address impliedCollateralService,
      ,
      ,
      address stabilizerNode,
      address swingTrader,
      address swingTraderManager
    ) = poolFactory.getCoreContracts(pool);
    (, address miningService, , , , address reinvestor) = poolFactory
      .getStakingContracts(pool);
    (, , address rewardOverflow, ) = poolFactory.getRewardSystemContracts(pool);
    (, address dexHandler, , , ) = poolFactory.getPeripheryContracts(pool);

    MiningService miningSvc = MiningService(miningService);

    bytes32 reinvestorRole = keccak256("REINVESTOR_ROLE");
    bytes32 buyerRole = keccak256("BUYER_ROLE");
    bytes32 adderRole = keccak256("LIQUIDITY_ADDER_ROLE");
    assertHasMaltRole(miningService, reinvestorRole, reinvestor);
    assertNotHasMaltRole(miningService, reinvestorRole, newReinvestor);
    assertHasMaltRole(dexHandler, buyerRole, reinvestor);
    assertNotHasMaltRole(dexHandler, buyerRole, newReinvestor);
    assertHasMaltRole(dexHandler, adderRole, reinvestor);
    assertNotHasMaltRole(dexHandler, adderRole, newReinvestor);

    // Assert all contracts have pointer to original contract
    assertEq(address(miningSvc.reinvestor()), reinvestor);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateReinvestor(pool, newReinvestor);

    vm.prank(admin);
    poolUpdater.updateReinvestor(pool, newReinvestor);

    // Assert pointers have now changed
    assertEq(address(miningSvc.reinvestor()), newReinvestor);
    assertHasMaltRole(miningService, reinvestorRole, newReinvestor);
    assertNotHasMaltRole(miningService, reinvestorRole, reinvestor);
    assertHasMaltRole(dexHandler, buyerRole, newReinvestor);
    assertNotHasMaltRole(dexHandler, buyerRole, reinvestor);
    assertHasMaltRole(dexHandler, adderRole, newReinvestor);
    assertNotHasMaltRole(dexHandler, adderRole, reinvestor);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.staking.reinvestor, newReinvestor);
  }

  function testFailsToUpdateVestingDist(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateVestingDistributor(randomPool, address(0x3023));
  }

  function testUpdateVestingDist(address randomUser, address newVestingDist)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newVestingDist != address(0));

    (address initialVestingDistributor, , , ) = poolFactory
      .getRewardSystemContracts(pool);
    vm.assume(newVestingDist != initialVestingDistributor);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateVestingDistributor(pool, newVestingDist);

    vm.prank(admin);
    poolUpdater.updateVestingDistributor(pool, newVestingDist);

    (address vestingDistributor, , , ) = poolFactory.getRewardSystemContracts(
      pool
    );

    assertTrue(initialVestingDistributor != vestingDistributor);
    assertEq(vestingDistributor, newVestingDist);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.rewardSystem.vestingDistributor, newVestingDist);
  }

  function testFailsToUpdateLinearDist(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateLinearDistributor(randomPool, address(0x3023));
  }

  function testUpdateLinearDist(address randomUser, address newLinearDist)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newLinearDist != address(0));

    (, address initialLinearDistributor, , ) = poolFactory
      .getRewardSystemContracts(pool);
    vm.assume(newLinearDist != initialLinearDistributor);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateLinearDistributor(pool, newLinearDist);

    vm.prank(admin);
    poolUpdater.updateLinearDistributor(pool, newLinearDist);

    (, address linearDistributor, , ) = poolFactory.getRewardSystemContracts(
      pool
    );

    assertTrue(initialLinearDistributor != linearDistributor);
    assertEq(linearDistributor, newLinearDist);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.rewardSystem.linearDistributor, newLinearDist);
  }

  function testFailsToUpdateOverflow(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateRewardOverflow(randomPool, address(0x3023));
  }

  function testUpdateOverflow(address randomUser, address newOverflow) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    assumeNoMaltContracts(newOverflow);

    (
      ,
      address auctionEscapeHatch,
      address impliedCollateralService,
      ,
      ,
      address stabilizerNode,
      address swingTrader,

    ) = poolFactory.getCoreContracts(pool);
    (, , , , , address reinvestor) = poolFactory.getStakingContracts(pool);
    (, , address rewardOverflow, address rewardThrottle) = poolFactory
      .getRewardSystemContracts(pool);
    (, address dexHandler, , , ) = poolFactory.getPeripheryContracts(pool);

    ImpliedCollateralService impCol = ImpliedCollateralService(
      impliedCollateralService
    );
    RewardThrottle throttle = RewardThrottle(rewardThrottle);

    bytes32 buyerRole = keccak256("BUYER_ROLE");
    bytes32 sellerRole = keccak256("BUYER_ROLE");
    assertHasMaltRole(dexHandler, buyerRole, rewardOverflow);
    assertNotHasMaltRole(dexHandler, buyerRole, newOverflow);
    assertHasMaltRole(dexHandler, sellerRole, rewardOverflow);
    assertNotHasMaltRole(dexHandler, sellerRole, newOverflow);

    // Assert all contracts have pointer to original contract
    assertEq(address(impCol.overflowPool()), rewardOverflow);
    assertEq(address(throttle.overflowPool()), rewardOverflow);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateRewardThrottle(pool, newOverflow);

    vm.prank(admin);
    poolUpdater.updateRewardOverflow(pool, newOverflow);

    // Assert pointers have now changed
    assertEq(address(impCol.overflowPool()), newOverflow);
    assertEq(address(throttle.overflowPool()), newOverflow);

    assertHasMaltRole(dexHandler, buyerRole, newOverflow);
    assertNotHasMaltRole(dexHandler, buyerRole, rewardOverflow);
    assertHasMaltRole(dexHandler, sellerRole, newOverflow);
    assertNotHasMaltRole(dexHandler, sellerRole, rewardOverflow);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.rewardSystem.rewardOverflow, newOverflow);
  }

  function testFailsToUpdateThrottle(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateRewardThrottle(randomPool, address(0x3023));
  }

  function testUpdateThrottle(address randomUser, address newThrottle) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newThrottle != address(0));

    (, , , , address profitDistributor, , , ) = poolFactory.getCoreContracts(
      pool
    );

    (
      address vestingDistributor,
      address linearDistributor,
      address rewardOverflow,
      address rewardThrottle
    ) = poolFactory.getRewardSystemContracts(pool);

    (, , , address keeper, ) = poolFactory.getPeripheryContracts(pool);

    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);
    VestingDistributor vestingDist = VestingDistributor(vestingDistributor);
    LinearDistributor linearDist = LinearDistributor(linearDistributor);
    RewardThrottleExtension keeperContract = RewardThrottleExtension(keeper);
    RewardOverflowPool overflow = RewardOverflowPool(rewardOverflow);

    // Assert all contracts have pointer to original contract
    assertEq(address(profitDist.rewardThrottle()), rewardThrottle);
    assertEq(address(vestingDist.rewardThrottle()), rewardThrottle);
    assertEq(address(linearDist.rewardThrottle()), rewardThrottle);
    assertEq(address(keeperContract.rewardThrottle()), rewardThrottle);
    assertEq(address(overflow.rewardThrottle()), rewardThrottle);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateRewardThrottle(pool, newThrottle);

    vm.prank(admin);
    poolUpdater.updateRewardThrottle(pool, newThrottle);

    // Assert pointers have now changed
    assertEq(address(profitDist.rewardThrottle()), newThrottle);
    assertEq(address(vestingDist.rewardThrottle()), newThrottle);
    assertEq(address(linearDist.rewardThrottle()), newThrottle);
    assertEq(address(keeperContract.rewardThrottle()), newThrottle);
    assertEq(address(overflow.rewardThrottle()), newThrottle);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.rewardSystem.rewardThrottle, newThrottle);
  }

  function testFailsToUpdateDataLab(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateDataLab(randomPool, address(0x3023));
  }

  function testUpdateDataLab(address randomUser, address newDataLab) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newDataLab != address(0));

    (
      address auction,
      ,
      address impliedCollateralService,
      address liquidityExtension,
      address profitDistributor,
      ,
      ,

    ) = poolFactory.getCoreContracts(pool);
    (address dataLab, , , , ) = poolFactory.getPeripheryContracts(pool);

    Auction auctionContract = Auction(auction);
    ImpliedCollateralService impCol = ImpliedCollateralService(
      impliedCollateralService
    );
    LiquidityExtension liqExt = LiquidityExtension(liquidityExtension);
    ProfitDistributor profitDist = ProfitDistributor(profitDistributor);

    // Assert all contracts have pointer to original contract
    assertEq(address(auctionContract.maltDataLab()), dataLab);
    assertEq(address(impCol.maltDataLab()), dataLab);
    assertEq(address(liqExt.maltDataLab()), dataLab);
    assertEq(address(profitDist.maltDataLab()), dataLab);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateDataLab(pool, newDataLab);

    vm.prank(admin);
    poolUpdater.updateDataLab(pool, newDataLab);

    // Assert pointers have now changed
    assertEq(address(auctionContract.maltDataLab()), newDataLab);
    assertEq(address(impCol.maltDataLab()), newDataLab);
    assertEq(address(liqExt.maltDataLab()), newDataLab);
    assertEq(address(profitDist.maltDataLab()), newDataLab);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.periphery.dataLab, newDataLab);
  }

  function testUpdateDataLabTwo(address randomUser, address newDataLab) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newDataLab != address(0));

    (
      ,
      ,
      ,
      ,
      ,
      address stabilizerNode,
      address swingTrader,
      address swingTraderManager
    ) = poolFactory.getCoreContracts(pool);
    (address dataLab, , , , ) = poolFactory.getPeripheryContracts(pool);

    StabilizerNode stabNode = StabilizerNode(stabilizerNode);
    SwingTrader swingTrade = SwingTrader(swingTrader);
    SwingTraderManager swingManager = SwingTraderManager(swingTraderManager);

    // Assert all contracts have pointer to original contract
    assertEq(address(stabNode.maltDataLab()), dataLab);
    assertEq(address(swingTrade.maltDataLab()), dataLab);
    assertEq(address(swingManager.maltDataLab()), dataLab);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateDataLab(pool, newDataLab);

    vm.prank(admin);
    poolUpdater.updateDataLab(pool, newDataLab);

    // Assert pointers have now changed
    assertEq(address(stabNode.maltDataLab()), newDataLab);
    assertEq(address(swingTrade.maltDataLab()), newDataLab);
    assertEq(address(swingManager.maltDataLab()), newDataLab);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.periphery.dataLab, newDataLab);
  }

  function testUpdateDataLabThree(address randomUser, address newDataLab)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newDataLab != address(0));

    (address bonding, , , , , ) = poolFactory.getStakingContracts(pool);

    (, , address rewardOverflow, ) = poolFactory.getRewardSystemContracts(pool);

    (
      address dataLab,
      address dexHandler,
      address transferVerifier,
      address keeper,

    ) = poolFactory.getPeripheryContracts(pool);

    Bonding bondingContract = Bonding(bonding);
    RewardOverflowPool overflow = RewardOverflowPool(rewardOverflow);
    DataLabExtension dex = DataLabExtension(dexHandler);
    PoolTransferVerification verifier = PoolTransferVerification(
      transferVerifier
    );
    DataLabExtension keeperContract = DataLabExtension(keeper);

    // Assert all contracts have pointer to original contract
    assertEq(address(bondingContract.maltDataLab()), dataLab);
    assertEq(address(overflow.maltDataLab()), dataLab);
    assertEq(address(dex.maltDataLab()), dataLab);
    assertEq(address(verifier.maltDataLab()), dataLab);
    assertEq(address(keeperContract.maltDataLab()), dataLab);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateDataLab(pool, newDataLab);

    vm.prank(admin);
    poolUpdater.updateDataLab(pool, newDataLab);

    // Assert pointers have now changed
    assertEq(address(bondingContract.maltDataLab()), newDataLab);
    assertEq(address(overflow.maltDataLab()), newDataLab);
    assertEq(address(dex.maltDataLab()), newDataLab);
    assertEq(address(verifier.maltDataLab()), newDataLab);
    assertEq(address(keeperContract.maltDataLab()), newDataLab);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.periphery.dataLab, newDataLab);
  }

  function testFailsToUpdateDexHandler(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateDexHandler(randomPool, address(0x3023));
  }

  function testUpdateDexHandler(address randomUser, address newDexHandler)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newDexHandler != address(0));

    (
      address auction,
      address auctionEscapeHatch,
      ,
      address liquidityExtension,
      ,
      address stabilizerNode,
      ,

    ) = poolFactory.getCoreContracts(pool);
    (, address dexHandler, address transferVerifier, , ) = poolFactory
      .getPeripheryContracts(pool);

    Auction auctionContract = Auction(auction);
    AuctionEscapeHatch escapeHatch = AuctionEscapeHatch(auctionEscapeHatch);
    LiquidityExtension liqExt = LiquidityExtension(liquidityExtension);
    StabilizerNode stabNode = StabilizerNode(stabilizerNode);
    PoolTransferVerification verifier = PoolTransferVerification(
      transferVerifier
    );

    assertTrue(verifier.whitelist(dexHandler));
    assertTrue(!verifier.whitelist(newDexHandler));

    // Assert all contracts have pointer to original contract
    assertEq(address(auctionContract.dexHandler()), dexHandler);
    assertEq(address(escapeHatch.dexHandler()), dexHandler);
    assertEq(address(liqExt.dexHandler()), dexHandler);
    assertEq(address(stabNode.dexHandler()), dexHandler);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateDexHandler(pool, newDexHandler);

    vm.prank(admin);
    poolUpdater.updateDexHandler(pool, newDexHandler);

    // Assert pointers have now changed
    assertEq(address(auctionContract.dexHandler()), newDexHandler);
    assertEq(address(escapeHatch.dexHandler()), newDexHandler);
    assertEq(address(liqExt.dexHandler()), newDexHandler);
    assertEq(address(stabNode.dexHandler()), newDexHandler);

    assertTrue(!verifier.whitelist(dexHandler));
    assertTrue(verifier.whitelist(newDexHandler));

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.periphery.dexHandler, newDexHandler);
  }

  function testUpdateDexHandlerTwo(address randomUser, address newDexHandler)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newDexHandler != address(0));

    (, , , , , address reinvestor) = poolFactory.getStakingContracts(pool);
    (, , address rewardOverflow, ) = poolFactory.getRewardSystemContracts(pool);
    (
      ,
      address dexHandler,
      address transferVerifier,
      address keeper,

    ) = poolFactory.getPeripheryContracts(pool);

    RewardReinvestor reinvest = RewardReinvestor(reinvestor);
    RewardOverflowPool overflow = RewardOverflowPool(rewardOverflow);
    DexHandlerExtension keeperContract = DexHandlerExtension(keeper);
    PoolTransferVerification verifier = PoolTransferVerification(
      transferVerifier
    );

    assertTrue(verifier.whitelist(dexHandler));
    assertTrue(!verifier.whitelist(newDexHandler));

    // Assert all contracts have pointer to original contract
    assertEq(address(reinvest.dexHandler()), dexHandler);
    assertEq(address(overflow.dexHandler()), dexHandler);
    assertEq(address(keeperContract.dexHandler()), dexHandler);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateDexHandler(pool, newDexHandler);

    vm.prank(admin);
    poolUpdater.updateDexHandler(pool, newDexHandler);

    // Assert pointers have now changed
    assertEq(address(reinvest.dexHandler()), newDexHandler);
    assertEq(address(overflow.dexHandler()), newDexHandler);
    assertEq(address(keeperContract.dexHandler()), newDexHandler);

    assertTrue(!verifier.whitelist(dexHandler));
    assertTrue(verifier.whitelist(newDexHandler));

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.periphery.dexHandler, newDexHandler);
  }

  function testUpdateDexHandlerThree(address randomUser, address newDexHandler)
    public
  {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newDexHandler != address(0));

    (, , , , , , address swingTrader, ) = poolFactory.getCoreContracts(pool);
    (address bonding, , , , , ) = poolFactory.getStakingContracts(pool);
    (, address dexHandler, address transferVerifier, , ) = poolFactory
      .getPeripheryContracts(pool);

    Bonding bondingContract = Bonding(bonding);
    SwingTrader swingTrade = SwingTrader(swingTrader);
    PoolTransferVerification verifier = PoolTransferVerification(
      transferVerifier
    );

    assertTrue(verifier.whitelist(dexHandler));
    assertTrue(!verifier.whitelist(newDexHandler));

    // Assert all contracts have pointer to original contract
    assertEq(address(bondingContract.dexHandler()), dexHandler);
    assertEq(address(swingTrade.dexHandler()), dexHandler);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateDexHandler(pool, newDexHandler);

    vm.prank(admin);
    poolUpdater.updateDexHandler(pool, newDexHandler);

    // Assert pointers have now changed
    assertEq(address(bondingContract.dexHandler()), newDexHandler);
    assertEq(address(swingTrade.dexHandler()), newDexHandler);

    assertTrue(!verifier.whitelist(dexHandler));
    assertTrue(verifier.whitelist(newDexHandler));

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.periphery.dexHandler, newDexHandler);
  }

  function testFailsToUpdateTransferVerifier(address randomPool) public {
    vm.assume(randomPool != address(0));
    vm.expectRevert("Unknown pool");
    poolUpdater.updateTransferVerifier(randomPool, address(0x3023));
  }

  function testUpdateTransferVerifier(
    address randomUser,
    address newTransferVerifier
  ) public {
    vm.assume(
      randomUser != admin && randomUser != address(0) && randomUser != timelock
    );
    vm.assume(newTransferVerifier != address(0));

    (, , address initialTransferVerifier, , ) = poolFactory
      .getPeripheryContracts(pool);

    address initialVerifier = transferService.verifiers(pool);

    assertEq(initialVerifier, initialTransferVerifier);

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolUpdater.updateTransferVerifier(pool, newTransferVerifier);

    vm.prank(admin);
    poolUpdater.updateTransferVerifier(pool, newTransferVerifier);

    (, , address transferVerifier, , ) = poolFactory.getPeripheryContracts(
      pool
    );

    assertTrue(initialTransferVerifier != transferVerifier);
    assertEq(transferVerifier, newTransferVerifier);

    address finalVerifier = transferService.verifiers(pool);

    assertEq(finalVerifier, newTransferVerifier);

    StabilizedPool memory currentPool = poolFactory.getStabilizedPool(pool);
    assertEq(currentPool.periphery.transferVerifier, newTransferVerifier);
  }

  function testProposingNewFactory(address randomUser) public {
    assumeNoMaltContracts(randomUser);

    StabilizedPoolFactory newFactory = new StabilizedPoolFactory(
      address(repository),
      admin,
      address(malt),
      address(globalIC),
      address(transferService),
      address(timekeeper)
    );

    assertEq(globalIC.proposedManager(), address(0));
    assertEq(transferService.proposedManager(), address(0));
    assertEq(malt.proposedManager(), address(0));

    vm.prank(randomUser);
    vm.expectRevert("Must have admin role");
    poolFactory.proposeNewFactory(pool, address(newFactory));

    vm.prank(admin);
    poolFactory.proposeNewFactory(pool, address(newFactory));

    // These all implement slightly different systems for updating the factory
    assertEq(malt.proposedManager(), address(newFactory));
    assertEq(transferService.proposedManager(), address(newFactory));
    assertEq(globalIC.proposedManager(), address(newFactory));
  }

  function testAcceptingNewFactoryRole(address randomUser) public {
    StabilizedPoolFactory newFactory = new StabilizedPoolFactory(
      address(repository),
      admin,
      address(malt),
      address(globalIC),
      address(transferService),
      address(timekeeper)
    );

    vm.startPrank(admin);
    newFactory.seedFromOldFactory(pool, address(poolFactory));

    vm.expectRevert("Must be proposedManager");
    newFactory.acceptFactoryPosition(pool);
    vm.stopPrank();

    bytes32 monetaryManagerRole = keccak256("MONETARY_MANAGER_ROLE");
    bytes32 verifierManagerRole = keccak256("VERIFIER_MANAGER_ROLE");
    assertHasMaltRole(address(malt), monetaryManagerRole, address(poolFactory));
    assertNotHasMaltRole(
      address(malt),
      monetaryManagerRole,
      address(newFactory)
    );
    assertHasMaltRole(
      address(transferService),
      verifierManagerRole,
      address(poolFactory)
    );
    assertNotHasMaltRole(
      address(transferService),
      verifierManagerRole,
      address(newFactory)
    );

    (, , , , , address stabilizerNode, , ) = newFactory.getCoreContracts(pool);
    (, address miningService, , , , ) = newFactory.getStakingContracts(pool);

    StabilizedPoolUnit stabNode = StabilizedPoolUnit(stabilizerNode);
    MiningService miningSvc = MiningService(miningService);

    assertEq(globalIC.proposedManager(), address(0));
    assertEq(transferService.proposedManager(), address(0));
    assertEq(malt.proposedManager(), address(0));

    assertEq(globalIC.updaterManager(), address(poolFactory));
    assertEq(transferService.verifierManager(), address(poolFactory));
    assertEq(malt.monetaryManager(), address(poolFactory));

    vm.startPrank(admin);
    poolFactory.proposeNewFactory(pool, address(newFactory));
    newFactory.acceptFactoryPosition(pool);
    vm.stopPrank();

    // The role has been accepted. proposedFactory should be addr(0)
    assertEq(globalIC.proposedManager(), address(0));
    assertEq(transferService.proposedManager(), address(0));
    assertEq(malt.proposedManager(), address(0));

    assertEq(globalIC.updaterManager(), address(newFactory));
    assertEq(transferService.verifierManager(), address(newFactory));
    assertEq(malt.monetaryManager(), address(newFactory));

    assertHasMaltRole(address(malt), monetaryManagerRole, address(newFactory));
    assertNotHasMaltRole(
      address(malt),
      monetaryManagerRole,
      address(poolFactory)
    );
    assertHasMaltRole(
      address(transferService),
      verifierManagerRole,
      address(newFactory)
    );
    assertNotHasMaltRole(
      address(transferService),
      verifierManagerRole,
      address(poolFactory)
    );
  }
}
