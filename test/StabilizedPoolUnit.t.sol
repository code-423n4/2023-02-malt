// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "../contracts/StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../contracts/StabilizedPoolExtensions/AuctionExtension.sol";
import "../contracts/StabilizedPoolExtensions/BondingExtension.sol";
import "../contracts/StabilizedPoolExtensions/DataLabExtension.sol";
import "../contracts/StabilizedPoolExtensions/DexHandlerExtension.sol";
import "../contracts/StabilizedPoolExtensions/GlobalICExtension.sol";
import "../contracts/StabilizedPoolExtensions/ImpliedCollateralServiceExtension.sol";
import "../contracts/StabilizedPoolExtensions/LiquidityExtensionExtension.sol";
import "../contracts/StabilizedPoolExtensions/MiningServiceExtension.sol";
import "../contracts/StabilizedPoolExtensions/ProfitDistributorExtension.sol";
import "../contracts/StabilizedPoolExtensions/RewardOverflowExtension.sol";
import "../contracts/StabilizedPoolExtensions/RewardThrottleExtension.sol";
import "../contracts/StabilizedPoolExtensions/StabilizerNodeExtension.sol";
import "../contracts/StabilizedPoolExtensions/SwingTraderExtension.sol";
import "../contracts/StabilizedPoolExtensions/SwingTraderManagerExtension.sol";

// Inherits all the extensions, which will all be tested against this single contract
contract MyPoolUnit is
  StabilizedPoolUnit,
  AuctionExtension,
  BondingExtension,
  DataLabExtension,
  DexHandlerExtension,
  GlobalICExtension,
  ImpliedCollateralServiceExtension,
  LiquidityExtensionExtension,
  MiningServiceExtension,
  ProfitDistributorExtension,
  RewardOverflowExtension,
  RewardThrottleExtension,
  StabilizerNodeExtension,
  SwingTraderExtension,
  SwingTraderManagerExtension
{
  constructor(
    address _timelock,
    address _repository,
    address poolFactory
  ) StabilizedPoolUnit(_timelock, _repository, poolFactory) {}

  function setupContracts(address _updater)
    external
    onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role")
  {
    _setPoolUpdater(_updater);
  }

  function _accessControl()
    internal
    override(
      AuctionExtension,
      BondingExtension,
      DataLabExtension,
      DexHandlerExtension,
      GlobalICExtension,
      ImpliedCollateralServiceExtension,
      LiquidityExtensionExtension,
      MiningServiceExtension,
      ProfitDistributorExtension,
      RewardOverflowExtension,
      RewardThrottleExtension,
      StabilizerNodeExtension,
      SwingTraderExtension,
      SwingTraderManagerExtension
    )
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}

contract PoolUnitTest is MaltTest {
  using stdStorage for StdStorage;

  MyPoolUnit poolUnit;

  address poolFactory = nextAddress();
  address poolUpdater = nextAddress();

  function setUp() public {
    poolUnit = new MyPoolUnit(timelock, address(repository), poolFactory);
    vm.prank(poolFactory);
    poolUnit.setupContracts(poolUpdater);

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

  function testCannotSetZeroAddressStabilizerNode() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setStablizerNode(address(0));
  }

  function testOnlyFactoryCanSetStabilizerNode(address user, address node)
    public
  {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setStablizerNode(node);

    IStabilizerNode initialStab = poolUnit.stabilizerNode();
    assertEq(address(initialStab), address(0));

    vm.prank(poolUpdater);
    poolUnit.setStablizerNode(node);

    IStabilizerNode finalStab = poolUnit.stabilizerNode();
    assertEq(address(finalStab), node);
  }

  function testCannotSetZeroAddressMaltDataLab() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setMaltDataLab(address(0));
  }

  function testOnlyFactoryCanSetMaltDataLab(address user, address node) public {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setMaltDataLab(node);

    IMaltDataLab initialDataLab = poolUnit.maltDataLab();
    assertEq(address(initialDataLab), address(0));

    vm.prank(poolUpdater);
    poolUnit.setMaltDataLab(node);

    IMaltDataLab finalDataLab = poolUnit.maltDataLab();
    assertEq(address(finalDataLab), node);
  }

  function testCannotSetZeroAddressDexHandler() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setDexHandler(address(0));
  }

  function testOnlyFactoryCanSetDexHandler(address user, address node) public {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setDexHandler(node);

    IDexHandler initialDexHandler = poolUnit.dexHandler();
    assertEq(address(initialDexHandler), address(0));

    vm.prank(poolUpdater);
    poolUnit.setDexHandler(node);

    IDexHandler finalDexHandler = poolUnit.dexHandler();
    assertEq(address(finalDexHandler), node);
  }

  function testCannotSetZeroAddressLiquidityEx() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setLiquidityExtension(address(0));
  }

  function testOnlyFactoryCanSetLiquidityEx(address user, address node) public {
    vm.assume(node != address(0));
    vm.assume(
      user != address(0) &&
        user != poolUpdater &&
        user != timelock &&
        user != timelock
    );

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setLiquidityExtension(node);

    ILiquidityExtension initialLiquidityEx = poolUnit.liquidityExtension();
    assertEq(address(initialLiquidityEx), address(0));

    vm.prank(poolUpdater);
    poolUnit.setLiquidityExtension(node);

    ILiquidityExtension finalLiquidityEx = poolUnit.liquidityExtension();
    assertEq(address(finalLiquidityEx), node);
  }

  function testCannotSetZeroAddressImCol() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setImpliedCollateralService(address(0));
  }

  function testOnlyFactoryCanSetImCol(address user, address node) public {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setImpliedCollateralService(node);

    IImpliedCollateralService initialImCol = poolUnit
      .impliedCollateralService();
    assertEq(address(initialImCol), address(0));

    vm.prank(poolUpdater);
    poolUnit.setImpliedCollateralService(node);

    IImpliedCollateralService finalImCol = poolUnit.impliedCollateralService();
    assertEq(address(finalImCol), node);
  }

  function testCannotSetZeroAddressAuction() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setAuction(address(0));
  }

  function testOnlyFactoryCanSetAuction(address user, address node) public {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setAuction(node);

    IAuction initialAuction = poolUnit.auction();
    assertEq(address(initialAuction), address(0));

    vm.prank(poolUpdater);
    poolUnit.setAuction(node);

    IAuction finalAuction = poolUnit.auction();
    assertEq(address(finalAuction), node);
  }

  function testCannotSetZeroAddressSwingTrader() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setSwingTrader(address(0));
  }

  function testOnlyFactoryCanSetSwingTrader(address user, address node) public {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setSwingTrader(node);

    ISwingTrader initialSwingTrader = poolUnit.swingTrader();
    assertEq(address(initialSwingTrader), address(0));

    vm.prank(poolUpdater);
    poolUnit.setSwingTrader(node);

    ISwingTrader finalSwingTrader = poolUnit.swingTrader();
    assertEq(address(finalSwingTrader), node);
  }

  function testCannotSetZeroAddressSwingTraderManager() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setSwingTraderManager(address(0));
  }

  function testOnlyFactoryCanSetSwingTraderManager(address user, address node)
    public
  {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setSwingTraderManager(node);

    ISwingTrader initialSwingTraderManager = poolUnit.swingTraderManager();
    assertEq(address(initialSwingTraderManager), address(0));

    vm.prank(poolUpdater);
    poolUnit.setSwingTraderManager(node);

    ISwingTrader finalSwingTraderManager = poolUnit.swingTraderManager();
    assertEq(address(finalSwingTraderManager), node);
  }

  function testCannotSetZeroAddressBonding() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setBonding(address(0));
  }

  function testOnlyFactoryCanSetBonding(address user, address node) public {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setBonding(node);

    IBonding initialBonding = poolUnit.bonding();
    assertEq(address(initialBonding), address(0));

    vm.prank(poolUpdater);
    poolUnit.setBonding(node);

    IBonding finalBonding = poolUnit.bonding();
    assertEq(address(finalBonding), node);
  }

  function testCannotSetZeroAddressOverflowPool() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setOverflowPool(address(0));
  }

  function testOnlyFactoryCanSetOverflowPoolBonding(address user, address node)
    public
  {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setOverflowPool(node);

    IOverflow initialOverflowPool = poolUnit.overflowPool();
    assertEq(address(initialOverflowPool), address(0));

    vm.prank(poolUpdater);
    poolUnit.setOverflowPool(node);

    IOverflow finalOverflowPool = poolUnit.overflowPool();
    assertEq(address(finalOverflowPool), node);
  }

  function testCannotSetZeroAddressRewardThrottle() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setRewardThrottle(address(0));
  }

  function testOnlyFactoryCanSetRewardThrottle(address user, address node)
    public
  {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setRewardThrottle(node);

    IRewardThrottle initialRewardThrottle = poolUnit.rewardThrottle();
    assertEq(address(initialRewardThrottle), address(0));

    vm.prank(poolUpdater);
    poolUnit.setRewardThrottle(node);

    IRewardThrottle finalRewardThrottle = poolUnit.rewardThrottle();
    assertEq(address(finalRewardThrottle), node);
  }

  function testCannotSetZeroAddressProfitDistributor() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setProfitDistributor(address(0));
  }

  function testOnlyFactoryCanSetProfitDistributor(address user, address node)
    public
  {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setProfitDistributor(node);

    IProfitDistributor initialProfitDistributor = poolUnit.profitDistributor();
    assertEq(address(initialProfitDistributor), address(0));

    vm.prank(poolUpdater);
    poolUnit.setProfitDistributor(node);

    IProfitDistributor finalProfitDistributor = poolUnit.profitDistributor();
    assertEq(address(finalProfitDistributor), node);
  }

  function testCannotSetZeroAddressMiningService() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setMiningService(address(0));
  }

  function testOnlyFactoryCanSetMiningService(address user, address node)
    public
  {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setMiningService(node);

    IMiningService initialMiningService = poolUnit.miningService();
    assertEq(address(initialMiningService), address(0));

    vm.prank(poolUpdater);
    poolUnit.setMiningService(node);

    IMiningService finalMiningService = poolUnit.miningService();
    assertEq(address(finalMiningService), node);
  }

  function testCannotSetZeroAddressGlobalIC() public {
    vm.expectRevert("Cannot use addr(0)");

    vm.prank(poolUpdater);
    poolUnit.setGlobalIC(address(0));
  }

  function testOnlyFactoryCanSetGlobalIC(address user, address node) public {
    vm.assume(node != address(0));
    vm.assume(user != address(0) && user != poolUpdater && user != timelock);

    vm.expectRevert("Must have pool updater role");
    vm.prank(user);
    poolUnit.setGlobalIC(node);

    IGlobalImpliedCollateralService initialGlobalIC = poolUnit.globalIC();
    assertEq(address(initialGlobalIC), address(0));

    vm.prank(poolUpdater);
    poolUnit.setGlobalIC(node);

    IGlobalImpliedCollateralService finalGlobalIC = poolUnit.globalIC();
    assertEq(address(finalGlobalIC), node);
  }
}
