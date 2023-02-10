// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../Permissions.sol";
import "./StabilizedPool.sol";
import "../interfaces/ITransferService.sol";
import "../interfaces/IGlobalImpliedCollateralService.sol";
import "../interfaces/IStabilizedPoolUpdater.sol";
import "../DataFeed/MaltDataLab.sol";
import "../StabilityPod/SwingTraderManager.sol";
import "../StabilityPod/ImpliedCollateralService.sol";
import "../StabilityPod/StabilizerNode.sol";
import "../StabilityPod/ProfitDistributor.sol";
import "../StabilityPod/LiquidityExtension.sol";
import "../DexHandlers/UniswapHandler.sol";
import "../RewardSystem/RewardOverflowPool.sol";
import "../RewardSystem/LinearDistributor.sol";
import "../RewardSystem/VestingDistributor.sol";
import "../RewardSystem/RewardThrottle.sol";
import "../Auction/Auction.sol";
import "../Auction/AuctionEscapeHatch.sol";
import "../Staking/Bonding.sol";
import "../Staking/ForfeitHandler.sol";
import "../Staking/MiningService.sol";
import "../Staking/ERC20VestedMine.sol";
import "../Staking/RewardMineBase.sol";
import "../Staking/RewardReinvestor.sol";
import "../Token/PoolTransferVerification.sol";
import "../Token/Malt.sol";
import "../ops/UniV2PoolKeeper.sol";

/// @title Stabilized Pool Factory
/// @author 0xScotch <scotch@malt.money>
/// @notice A factory that can deploy all the contracts for a given pool
contract StabilizedPoolFactory is Permissions {
  address public immutable malt;

  bytes32 public immutable POOL_UPDATER_ROLE;

  address public timekeeper;
  IGlobalImpliedCollateralService public globalIC;
  ITransferService public transferService;

  address[] public pools;
  mapping(address => StabilizedPool) public stabilizedPools;

  event NewStabilizedPool(address indexed pool);
  event SetTimekeeper(address timekeeper);

  constructor(
    address _repository,
    address initialAdmin,
    address _malt,
    address _globalIC,
    address _transferService,
    address _timekeeper
  ) {
    malt = _malt;

    require(_repository != address(0), "pod: repository");
    require(_malt != address(0), "pod: malt");
    require(initialAdmin != address(0), "pod: admin");
    require(_globalIC != address(0), "pod: globalIC");
    require(_timekeeper != address(0), "pod: timekeeper");
    require(_transferService != address(0), "pod: xfer");

    POOL_UPDATER_ROLE = 0xb70e81d43273d7b57d823256e2fd3d6bb0b670e5f5e1253ffd1c5f776a989c34;
    _initialSetup(_repository);
    _roleSetup(
      0xb70e81d43273d7b57d823256e2fd3d6bb0b670e5f5e1253ffd1c5f776a989c34,
      initialAdmin
    );

    timekeeper = _timekeeper;
    globalIC = IGlobalImpliedCollateralService(_globalIC);
    transferService = ITransferService(_transferService);
  }

  function setCurrentPool(address pool, StabilizedPool memory currentPool)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role")
  {
    StabilizedPool storage existingPool = stabilizedPools[pool];
    require(currentPool.pool != address(0), "Addr(0)");
    require(currentPool.pool == existingPool.pool, "Unknown pool");

    if (
      currentPool.updater != address(0) &&
      existingPool.updater != address(0) &&
      currentPool.updater != existingPool.updater
    ) {
      _transferRole(
        currentPool.updater,
        existingPool.updater,
        POOL_UPDATER_ROLE
      );
      existingPool.updater = currentPool.updater;
    }

    if (
      currentPool.core.impliedCollateralService != address(0) &&
      existingPool.core.impliedCollateralService != address(0) &&
      currentPool.core.impliedCollateralService !=
      existingPool.core.impliedCollateralService
    ) {
      globalIC.setPoolUpdater(pool, currentPool.core.impliedCollateralService);
    }

    if (
      currentPool.periphery.transferVerifier != address(0) &&
      existingPool.periphery.transferVerifier != address(0) &&
      currentPool.periphery.transferVerifier !=
      existingPool.periphery.transferVerifier
    ) {
      transferService.removeVerifier(pool);
      transferService.addVerifier(pool, currentPool.periphery.transferVerifier);
    }

    if (
      currentPool.core.auctionEscapeHatch != address(0) &&
      existingPool.core.auctionEscapeHatch != address(0) &&
      currentPool.core.auctionEscapeHatch !=
      existingPool.core.auctionEscapeHatch
    ) {
      Malt(malt).removeMinter(existingPool.core.auctionEscapeHatch);
      Malt(malt).addMinter(currentPool.core.auctionEscapeHatch);
    }

    if (
      currentPool.core.liquidityExtension != address(0) &&
      existingPool.core.liquidityExtension != address(0) &&
      currentPool.core.liquidityExtension !=
      existingPool.core.liquidityExtension
    ) {
      Malt(malt).removeBurner(existingPool.core.liquidityExtension);
      Malt(malt).addBurner(currentPool.core.liquidityExtension);
    }

    if (
      currentPool.core.stabilizerNode != address(0) &&
      existingPool.core.stabilizerNode != address(0) &&
      currentPool.core.stabilizerNode != existingPool.core.stabilizerNode
    ) {
      Malt(malt).removeMinter(existingPool.core.stabilizerNode);
      Malt(malt).addMinter(currentPool.core.stabilizerNode);
    }

    existingPool.core = currentPool.core;
    existingPool.staking = currentPool.staking;
    existingPool.rewardSystem = currentPool.rewardSystem;
    existingPool.periphery = currentPool.periphery;
  }

  function initializeStabilizedPool(
    address pool,
    string memory name,
    address collateralToken,
    address updater
  ) external onlyRoleMalt(ADMIN_ROLE, "Must have admin role") {
    require(pool != address(0), "addr(0)");
    require(collateralToken != address(0), "addr(0)");
    StabilizedPool storage currentPool = stabilizedPools[pool];
    require(currentPool.collateralToken == address(0), "already initialized");

    currentPool.collateralToken = collateralToken;
    currentPool.name = name;
    currentPool.updater = updater;
    currentPool.pool = pool;
    _setupRole(POOL_UPDATER_ROLE, updater);

    pools.push(pool);

    emit NewStabilizedPool(pool);
  }

  function setupUniv2StabilizedPool(address pool)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool storage currentPool = stabilizedPools[pool];
    require(currentPool.collateralToken != address(0), "Unknown pool");
    require(currentPool.updater != address(0), "updater");

    IStabilizedPoolUpdater(currentPool.updater).validatePoolDeployment(pool);

    _setup(pool);

    transferService.addVerifier(pool, currentPool.periphery.transferVerifier);
    Malt(malt).addMinter(currentPool.core.auctionEscapeHatch);
    Malt(malt).addMinter(currentPool.core.stabilizerNode);
    Malt(malt).addBurner(currentPool.core.liquidityExtension);
    globalIC.setPoolUpdater(pool, currentPool.core.impliedCollateralService);
  }

  function setTimekeeper(address _timekeeper)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_timekeeper != address(0), "addr(0)");

    Malt(malt).removeMinter(timekeeper);
    Malt(malt).addMinter(_timekeeper);

    timekeeper = _timekeeper;
    emit SetTimekeeper(_timekeeper);
  }

  function seedFromOldFactory(address pool, address oldFactory)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool storage currentPool = stabilizedPools[pool];
    require(currentPool.collateralToken == address(0), "already active");

    StabilizedPool memory oldPool = StabilizedPoolFactory(oldFactory)
      .getStabilizedPool(pool);
    require(oldPool.collateralToken != address(0), "Unknown pool");

    currentPool.name = oldPool.name;
    currentPool.collateralToken = oldPool.collateralToken;
    currentPool.updater = oldPool.updater;
    currentPool.core = oldPool.core;
    currentPool.staking = oldPool.staking;
    currentPool.rewardSystem = oldPool.rewardSystem;
    currentPool.periphery = oldPool.periphery;
  }

  function getStabilizedPool(address pool)
    external
    view
    returns (StabilizedPool memory)
  {
    StabilizedPool storage currentPool = stabilizedPools[pool];
    return currentPool;
  }

  function getCoreContracts(address pool)
    external
    view
    returns (
      address auction,
      address auctionEscapeHatch,
      address impliedCollateralService,
      address liquidityExtension,
      address profitDistributor,
      address stabilizerNode,
      address swingTrader,
      address swingTraderManager
    )
  {
    StabilizedPool storage currentPool = stabilizedPools[pool];

    return (
      currentPool.core.auction,
      currentPool.core.auctionEscapeHatch,
      currentPool.core.impliedCollateralService,
      currentPool.core.liquidityExtension,
      currentPool.core.profitDistributor,
      currentPool.core.stabilizerNode,
      currentPool.core.swingTrader,
      currentPool.core.swingTraderManager
    );
  }

  function getStakingContracts(address pool)
    external
    view
    returns (
      address bonding,
      address miningService,
      address vestedMine,
      address forfeitHandler,
      address linearMine,
      address reinvestor
    )
  {
    StabilizedPool storage currentPool = stabilizedPools[pool];

    return (
      currentPool.staking.bonding,
      currentPool.staking.miningService,
      currentPool.staking.vestedMine,
      currentPool.staking.forfeitHandler,
      currentPool.staking.linearMine,
      currentPool.staking.reinvestor
    );
  }

  function getRewardSystemContracts(address pool)
    external
    view
    returns (
      address vestingDistributor,
      address linearDistributor,
      address rewardOverflow,
      address rewardThrottle
    )
  {
    StabilizedPool storage currentPool = stabilizedPools[pool];

    return (
      currentPool.rewardSystem.vestingDistributor,
      currentPool.rewardSystem.linearDistributor,
      currentPool.rewardSystem.rewardOverflow,
      currentPool.rewardSystem.rewardThrottle
    );
  }

  function getPeripheryContracts(address pool)
    external
    view
    returns (
      address dataLab,
      address dexHandler,
      address transferVerifier,
      address keeper,
      address dualMA
    )
  {
    StabilizedPool storage currentPool = stabilizedPools[pool];

    return (
      currentPool.periphery.dataLab,
      currentPool.periphery.dexHandler,
      currentPool.periphery.transferVerifier,
      currentPool.periphery.keeper,
      currentPool.periphery.dualMA
    );
  }

  function getPool(address pool)
    external
    view
    returns (
      address collateralToken,
      address updater,
      string memory name
    )
  {
    StabilizedPool storage currentPool = stabilizedPools[pool];

    return (currentPool.collateralToken, currentPool.updater, currentPool.name);
  }

  function _setup(address pool) internal {
    StabilizedPool storage currentPool = stabilizedPools[pool];
    address localGlobalIC = address(globalIC); // gas

    Auction(currentPool.core.auction).setupContracts(
      currentPool.collateralToken,
      currentPool.core.liquidityExtension,
      currentPool.core.stabilizerNode,
      currentPool.periphery.dataLab,
      currentPool.periphery.dexHandler,
      currentPool.core.auctionEscapeHatch,
      currentPool.core.profitDistributor,
      pool
    );
    AuctionEscapeHatch(currentPool.core.auctionEscapeHatch).setupContracts(
      malt,
      currentPool.collateralToken,
      currentPool.core.auction,
      currentPool.periphery.dexHandler,
      pool
    );
    ImpliedCollateralService(currentPool.core.impliedCollateralService)
      .setupContracts(
        currentPool.collateralToken,
        malt,
        pool,
        currentPool.core.auction,
        currentPool.rewardSystem.rewardOverflow,
        currentPool.core.swingTraderManager,
        currentPool.core.liquidityExtension,
        currentPool.periphery.dataLab,
        currentPool.core.stabilizerNode,
        localGlobalIC
      );
    LiquidityExtension(currentPool.core.liquidityExtension).setupContracts(
      currentPool.core.auction,
      currentPool.collateralToken,
      malt,
      currentPool.periphery.dexHandler,
      currentPool.periphery.dataLab,
      currentPool.core.swingTrader,
      pool
    );
    ProfitDistributor(currentPool.core.profitDistributor).setupContracts(
      malt,
      currentPool.collateralToken,
      localGlobalIC,
      currentPool.rewardSystem.rewardThrottle,
      currentPool.core.swingTrader,
      currentPool.core.liquidityExtension,
      currentPool.core.auction,
      currentPool.periphery.dataLab,
      currentPool.core.impliedCollateralService,
      pool
    );
    StabilizerNode(currentPool.core.stabilizerNode).setupContracts(
      malt,
      currentPool.collateralToken,
      currentPool.periphery.dexHandler,
      currentPool.periphery.dataLab,
      currentPool.core.impliedCollateralService,
      currentPool.core.auction,
      currentPool.core.swingTraderManager,
      currentPool.core.profitDistributor,
      pool
    );
    SwingTrader(currentPool.core.swingTrader).setupContracts(
      currentPool.collateralToken,
      malt,
      currentPool.periphery.dexHandler,
      currentPool.core.swingTraderManager,
      currentPool.periphery.dataLab,
      currentPool.core.profitDistributor,
      pool
    );
    SwingTraderManager(currentPool.core.swingTraderManager).setupContracts(
      currentPool.collateralToken,
      malt,
      currentPool.core.stabilizerNode,
      currentPool.periphery.dataLab,
      currentPool.core.swingTrader,
      currentPool.rewardSystem.rewardOverflow,
      pool
    );
    Bonding(currentPool.staking.bonding).setupContracts(
      malt,
      currentPool.collateralToken,
      pool,
      currentPool.staking.miningService,
      currentPool.periphery.dexHandler,
      currentPool.periphery.dataLab,
      currentPool.rewardSystem.vestingDistributor,
      currentPool.rewardSystem.linearDistributor
    );
    MiningService(currentPool.staking.miningService).setupContracts(
      currentPool.staking.reinvestor,
      currentPool.staking.bonding,
      currentPool.staking.vestedMine,
      currentPool.staking.linearMine,
      pool
    );
    ERC20VestedMine(currentPool.staking.vestedMine).setupContracts(
      currentPool.staking.miningService,
      currentPool.rewardSystem.vestingDistributor,
      currentPool.staking.bonding,
      currentPool.collateralToken,
      pool
    );
    ForfeitHandler(currentPool.staking.forfeitHandler).setupContracts(
      currentPool.collateralToken,
      currentPool.core.swingTrader,
      pool
    );
    RewardMineBase(currentPool.staking.linearMine).setupContracts(
      currentPool.staking.miningService,
      currentPool.rewardSystem.linearDistributor,
      currentPool.staking.bonding,
      currentPool.collateralToken,
      pool
    );
    RewardReinvestor(currentPool.staking.reinvestor).setupContracts(
      malt,
      currentPool.collateralToken,
      currentPool.periphery.dexHandler,
      currentPool.staking.bonding,
      pool,
      currentPool.staking.miningService
    );
    VestingDistributor(currentPool.rewardSystem.vestingDistributor)
      .setupContracts(
        currentPool.collateralToken,
        currentPool.staking.vestedMine,
        currentPool.rewardSystem.rewardThrottle,
        currentPool.staking.forfeitHandler,
        pool
      );
    LinearDistributor(currentPool.rewardSystem.linearDistributor)
      .setupContracts(
        currentPool.collateralToken,
        currentPool.staking.linearMine,
        currentPool.rewardSystem.rewardThrottle,
        currentPool.staking.forfeitHandler,
        currentPool.rewardSystem.vestingDistributor,
        pool
      );
    RewardOverflowPool(currentPool.rewardSystem.rewardOverflow).setupContracts(
      currentPool.collateralToken,
      malt,
      currentPool.periphery.dexHandler,
      currentPool.core.swingTraderManager,
      currentPool.periphery.dataLab,
      currentPool.core.profitDistributor,
      currentPool.rewardSystem.rewardThrottle,
      pool
    );
    RewardThrottle(currentPool.rewardSystem.rewardThrottle).setupContracts(
      currentPool.collateralToken,
      currentPool.rewardSystem.rewardOverflow,
      currentPool.staking.bonding,
      pool
    );
    MaltDataLab(currentPool.periphery.dataLab).setupContracts(
      malt,
      currentPool.collateralToken,
      pool,
      currentPool.periphery.dualMA,
      currentPool.periphery.swingTraderMaltRatioMA,
      currentPool.core.impliedCollateralService,
      currentPool.core.swingTraderManager,
      localGlobalIC,
      currentPool.periphery.keeper
    );

    address[] memory buyers = new address[](4);
    buyers[0] = currentPool.staking.reinvestor;
    buyers[1] = currentPool.core.swingTrader;
    buyers[2] = currentPool.rewardSystem.rewardOverflow;
    buyers[3] = currentPool.core.liquidityExtension;
    address[] memory sellers = new address[](4);
    sellers[0] = currentPool.core.auctionEscapeHatch;
    sellers[1] = currentPool.core.swingTrader;
    sellers[2] = currentPool.rewardSystem.rewardOverflow;
    sellers[3] = currentPool.core.stabilizerNode;
    address[] memory adders = new address[](1);
    adders[0] = currentPool.staking.reinvestor;
    address[] memory removers = new address[](1);
    removers[0] = currentPool.staking.bonding;

    IDexHandler(currentPool.periphery.dexHandler).setupContracts(
      malt,
      currentPool.collateralToken,
      pool,
      currentPool.periphery.dataLab,
      buyers,
      sellers,
      adders,
      removers
    );
    PoolTransferVerification(currentPool.periphery.transferVerifier)
      .setupContracts(
        currentPool.periphery.dataLab,
        pool,
        currentPool.periphery.dexHandler,
        currentPool.core.stabilizerNode
      );
    IKeeperCompatibleInterface(currentPool.periphery.keeper).setupContracts(
      currentPool.periphery.dataLab,
      currentPool.periphery.dexHandler,
      currentPool.rewardSystem.vestingDistributor,
      currentPool.rewardSystem.rewardThrottle,
      pool,
      currentPool.core.stabilizerNode,
      currentPool.core.auction,
      currentPool.core.swingTraderManager
    );
  }

  function proposeNewFactory(address pool, address _factory)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = stabilizedPools[pool];
    require(_factory != address(0), "Not addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    globalIC.proposeNewUpdaterManager(_factory);
    transferService.proposeNewVerifierManager(_factory);
    Malt(malt).proposeNewManager(_factory);
  }

  function acceptFactoryPosition(address pool)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = stabilizedPools[pool];
    require(currentPool.collateralToken != address(0), "Unknown pool");

    globalIC.acceptUpdaterManagerRole();
    transferService.acceptVerifierManagerRole();
    Malt(malt).acceptManagerRole();
  }
}
