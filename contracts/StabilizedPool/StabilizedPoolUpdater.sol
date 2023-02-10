// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../Permissions.sol";

import "./StabilizedPool.sol";
import "../interfaces/IStabilizedPoolFactory.sol";
import "../DataFeed/MaltDataLab.sol";
import "../StabilityPod/SwingTraderManager.sol";
import "../StabilityPod/ImpliedCollateralService.sol";
import "../StabilityPod/StabilizerNode.sol";
import "../StabilityPod/ProfitDistributor.sol";
import "../StabilityPod/LiquidityExtension.sol";
import "../RewardSystem/RewardOverflowPool.sol";
import "../RewardSystem/LinearDistributor.sol";
import "../DexHandlers/UniswapHandler.sol";
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
import "../ops/UniV2PoolKeeper.sol";

/// @title Stabilized Pool Updater
/// @author 0xScotch <scotch@malt.money>
/// @notice A contract that can update contract points within a stabilized pool
contract StabilizedPoolUpdater is Permissions {
  IStabilizedPoolFactory public factory;

  constructor(address _repository, address _factory) {
    require(_repository != address(0), "StabilizerPodFactory: Repo addr(0)");
    require(_factory != address(0), "StabilizerPodFactory: Factory addr(0)");

    _initialSetup(_repository);

    factory = IStabilizedPoolFactory(_factory);
  }

  function updateTimekeeper(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    Bonding(currentPool.staking.bonding).setTimekeeper(_new);
    RewardThrottle(currentPool.rewardSystem.rewardThrottle).setTimekeeper(_new);
    UniV2PoolKeeper(currentPool.periphery.keeper).setTimekeeper(_new);
  }

  function updateDAO(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    ProfitDistributor(currentPool.core.profitDistributor).setDAO(_new);
  }

  function updateTreasury(address pool, address payable _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    ProfitDistributor(currentPool.core.profitDistributor).setTreasury(_new);
    ForfeitHandler(currentPool.staking.forfeitHandler).setTreasury(_new);
    RewardReinvestor(currentPool.staking.reinvestor).setTreasury(_new);
    IKeeperCompatibleInterface(currentPool.periphery.keeper).setTreasury(_new);
  }

  function updateGlobalIC(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    ImpliedCollateralService(currentPool.core.impliedCollateralService)
      .setGlobalIC(_new);
    ProfitDistributor(currentPool.core.profitDistributor).setGlobalIC(_new);
    MaltDataLab(currentPool.periphery.dataLab).setGlobalIC(_new);
  }

  function updateAuction(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    AuctionEscapeHatch(currentPool.core.auctionEscapeHatch).setAuction(_new);
    ImpliedCollateralService(currentPool.core.impliedCollateralService)
      .setAuction(_new);
    LiquidityExtension(currentPool.core.liquidityExtension).setAuction(_new);
    ProfitDistributor(currentPool.core.profitDistributor).setAuction(_new);
    StabilizerNode(currentPool.core.stabilizerNode).setAuction(_new);
    AuctionExtension(currentPool.periphery.keeper).setAuction(_new);

    currentPool.core.auction = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateAuctionEscapeHatch(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    Auction(currentPool.core.auction).setAuctionAmender(_new);

    IDexHandler(currentPool.periphery.dexHandler).removeSeller(
      currentPool.core.auctionEscapeHatch
    );
    IDexHandler(currentPool.periphery.dexHandler).addSeller(_new);

    currentPool.core.auctionEscapeHatch = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateImpliedCollateralService(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    ProfitDistributor(currentPool.core.profitDistributor)
      .setImpliedCollateralService(_new);
    StabilizerNode(currentPool.core.stabilizerNode).setImpliedCollateralService(
        _new
      );
    MaltDataLab(currentPool.periphery.dataLab).setImpliedCollateralService(
      _new
    );

    currentPool.core.impliedCollateralService = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateLiquidityExtension(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    Auction(currentPool.core.auction).setLiquidityExtension(_new);
    ImpliedCollateralService(currentPool.core.impliedCollateralService)
      .setLiquidityExtension(_new);
    ProfitDistributor(currentPool.core.profitDistributor).setLiquidityExtension(
        _new
      );

    currentPool.core.liquidityExtension = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateProfitDistributor(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    Auction(currentPool.core.auction).setProfitDistributor(_new);
    StabilizerNode(currentPool.core.stabilizerNode).setProfitDistributor(_new);
    SwingTrader(currentPool.core.swingTrader).setProfitDistributor(_new);
    RewardOverflowPool(currentPool.rewardSystem.rewardOverflow)
      .setProfitDistributor(_new);

    currentPool.core.profitDistributor = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateStabilizerNode(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    PoolTransferVerification(currentPool.periphery.transferVerifier)
      .setStablizerNode(_new);
    Auction(currentPool.core.auction).setStablizerNode(_new);
    ImpliedCollateralService(currentPool.core.impliedCollateralService)
      .setStablizerNode(_new);
    SwingTraderManager(currentPool.core.swingTraderManager).setStablizerNode(
      _new
    );

    IDexHandler(currentPool.periphery.dexHandler).removeSeller(
      currentPool.core.stabilizerNode
    );
    IDexHandler(currentPool.periphery.dexHandler).addSeller(_new);

    currentPool.core.stabilizerNode = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateSwingTrader(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    LiquidityExtension(currentPool.core.liquidityExtension).setSwingTrader(
      _new
    );
    ProfitDistributor(currentPool.core.profitDistributor).setSwingTrader(_new);
    // remember to also add the new swing trader to the SwingTraderManager

    IDexHandler(currentPool.periphery.dexHandler).removeBuyer(
      currentPool.core.swingTrader
    );
    IDexHandler(currentPool.periphery.dexHandler).removeSeller(
      currentPool.core.swingTrader
    );
    IDexHandler(currentPool.periphery.dexHandler).addBuyer(_new);
    IDexHandler(currentPool.periphery.dexHandler).addSeller(_new);

    currentPool.core.swingTrader = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateSwingTraderManager(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    ImpliedCollateralService(currentPool.core.impliedCollateralService)
      .setSwingTraderManager(_new);
    StabilizerNode(currentPool.core.stabilizerNode).setSwingTraderManager(_new);
    SwingTrader(currentPool.core.swingTrader).setSwingTraderManager(_new);
    RewardOverflowPool(currentPool.rewardSystem.rewardOverflow)
      .setSwingTraderManager(_new);
    MaltDataLab(currentPool.periphery.dataLab).setSwingTraderManager(_new);

    currentPool.core.swingTraderManager = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateVestedMine(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    currentPool.staking.vestedMine = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateForfeitHandler(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    VestingDistributor(currentPool.rewardSystem.vestingDistributor)
      .setForfeitor(_new);
    LinearDistributor(currentPool.rewardSystem.linearDistributor).setForfeitor(
      _new
    );

    currentPool.staking.forfeitHandler = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateBonding(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    MiningService(currentPool.staking.miningService).setBonding(_new);
    RewardReinvestor(currentPool.staking.reinvestor).setBonding(_new);
    RewardThrottle(currentPool.rewardSystem.rewardThrottle).setBonding(_new);

    IDexHandler(currentPool.periphery.dexHandler).removeLiquidityRemover(
      currentPool.staking.bonding
    );
    IDexHandler(currentPool.periphery.dexHandler).addLiquidityRemover(_new);

    currentPool.staking.bonding = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateMiningService(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    Bonding(currentPool.staking.bonding).setMiningService(_new);
    ERC20VestedMine(currentPool.staking.vestedMine).setMiningService(_new);
    RewardMineBase(currentPool.staking.linearMine).setMiningService(_new);
    RewardReinvestor(currentPool.staking.reinvestor).setMiningService(_new);

    currentPool.staking.miningService = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateLinearMine(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    currentPool.staking.linearMine = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateReinvestor(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    MiningService(currentPool.staking.miningService).setReinvestor(_new);

    IDexHandler(currentPool.periphery.dexHandler).removeBuyer(
      currentPool.staking.reinvestor
    );
    IDexHandler(currentPool.periphery.dexHandler).removeLiquidityAdder(
      currentPool.staking.reinvestor
    );
    IDexHandler(currentPool.periphery.dexHandler).addBuyer(_new);
    IDexHandler(currentPool.periphery.dexHandler).addLiquidityAdder(_new);

    currentPool.staking.reinvestor = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateVestingDistributor(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    currentPool.rewardSystem.vestingDistributor = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateLinearDistributor(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    currentPool.rewardSystem.linearDistributor = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateRewardOverflow(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    ImpliedCollateralService(currentPool.core.impliedCollateralService)
      .setOverflowPool(_new);
    RewardThrottle(currentPool.rewardSystem.rewardThrottle).setOverflowPool(
      _new
    );

    IDexHandler(currentPool.periphery.dexHandler).removeBuyer(
      currentPool.rewardSystem.rewardOverflow
    );
    IDexHandler(currentPool.periphery.dexHandler).removeSeller(
      currentPool.rewardSystem.rewardOverflow
    );
    IDexHandler(currentPool.periphery.dexHandler).addBuyer(_new);
    IDexHandler(currentPool.periphery.dexHandler).addSeller(_new);

    currentPool.rewardSystem.rewardOverflow = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateRewardThrottle(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    ProfitDistributor(currentPool.core.profitDistributor).setRewardThrottle(
      _new
    );
    VestingDistributor(currentPool.rewardSystem.vestingDistributor)
      .setRewardThrottle(_new);
    LinearDistributor(currentPool.rewardSystem.linearDistributor)
      .setRewardThrottle(_new);
    RewardThrottleExtension(currentPool.periphery.keeper).setRewardThrottle(
      _new
    );
    RewardOverflowPool(currentPool.rewardSystem.rewardOverflow)
      .setRewardThrottle(_new);

    currentPool.rewardSystem.rewardThrottle = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateDataLab(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    Auction(currentPool.core.auction).setMaltDataLab(_new);
    ImpliedCollateralService(currentPool.core.impliedCollateralService)
      .setMaltDataLab(_new);
    LiquidityExtension(currentPool.core.liquidityExtension).setMaltDataLab(
      _new
    );
    ProfitDistributor(currentPool.core.profitDistributor).setMaltDataLab(_new);
    StabilizerNode(currentPool.core.stabilizerNode).setMaltDataLab(_new);
    SwingTrader(currentPool.core.swingTrader).setMaltDataLab(_new);
    SwingTraderManager(currentPool.core.swingTraderManager).setMaltDataLab(
      _new
    );
    Bonding(currentPool.staking.bonding).setMaltDataLab(_new);
    RewardOverflowPool(currentPool.rewardSystem.rewardOverflow).setMaltDataLab(
      _new
    );
    DataLabExtension(currentPool.periphery.dexHandler).setMaltDataLab(_new);
    PoolTransferVerification(currentPool.periphery.transferVerifier)
      .setMaltDataLab(_new);
    DataLabExtension(currentPool.periphery.keeper).setMaltDataLab(_new);

    currentPool.periphery.dataLab = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateDexHandler(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    Auction(currentPool.core.auction).setDexHandler(_new);
    AuctionEscapeHatch(currentPool.core.auctionEscapeHatch).setDexHandler(_new);
    LiquidityExtension(currentPool.core.liquidityExtension).setDexHandler(_new);
    StabilizerNode(currentPool.core.stabilizerNode).setDexHandler(_new);
    SwingTrader(currentPool.core.swingTrader).setDexHandler(_new);
    Bonding(currentPool.staking.bonding).setDexHandler(_new);
    RewardReinvestor(currentPool.staking.reinvestor).setDexHandler(_new);
    RewardOverflowPool(currentPool.rewardSystem.rewardOverflow).setDexHandler(
      _new
    );
    DexHandlerExtension(currentPool.periphery.keeper).setDexHandler(_new);

    PoolTransferVerification(currentPool.periphery.transferVerifier)
      .removeFromWhitelist(currentPool.periphery.dexHandler);
    PoolTransferVerification(currentPool.periphery.transferVerifier)
      .addToWhitelist(_new);

    currentPool.periphery.dexHandler = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function updateTransferVerifier(address pool, address _new)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    StabilizedPool memory currentPool = _getCurrentPool(pool);
    require(_new != address(0), "No addr(0)");
    require(currentPool.collateralToken != address(0), "Unknown pool");

    currentPool.periphery.transferVerifier = _new;
    _updateCurrentPool(pool, currentPool);
  }

  function validatePoolDeployment(address pool) external {
    StabilizedPool memory currentPool = _getCurrentPool(pool);

    require(currentPool.core.auction != address(0), "auction");
    require(
      currentPool.core.auctionEscapeHatch != address(0),
      "EscapeHatchnot deployed"
    );
    require(
      currentPool.core.impliedCollateralService != address(0),
      "ImpColSvc"
    );
    require(currentPool.core.liquidityExtension != address(0), "LiqExt");
    require(currentPool.core.stabilizerNode != address(0), "StabilizerNode");
    require(currentPool.core.profitDistributor != address(0), "ProfitDist");
    require(currentPool.core.swingTrader != address(0), "SwingTrader");
    require(
      currentPool.core.swingTraderManager != address(0),
      "SwingTraderManager"
    );
    require(currentPool.staking.bonding != address(0), "Bonding");
    require(currentPool.staking.miningService != address(0), "MiningSvc");
    require(currentPool.staking.vestedMine != address(0), "VestedMine");
    require(currentPool.staking.linearMine != address(0), "LinearMine");
    require(currentPool.staking.forfeitHandler != address(0), "ForfeitHandler");
    require(currentPool.staking.reinvestor != address(0), "Reinvestor");
    require(
      currentPool.rewardSystem.vestingDistributor != address(0),
      "VestingDist"
    );
    require(
      currentPool.rewardSystem.linearDistributor != address(0),
      "LinearDist"
    );
    require(currentPool.rewardSystem.rewardOverflow != address(0), "Overflow");
    require(currentPool.rewardSystem.rewardThrottle != address(0), "Throttle");
    require(currentPool.periphery.dataLab != address(0), "DataLab");
    require(currentPool.periphery.dualMA != address(0), "dualMA");
    require(
      currentPool.periphery.swingTraderMaltRatioMA != address(0),
      "ratioMA"
    );
    require(currentPool.periphery.dexHandler != address(0), "DexHandler");
    require(
      currentPool.periphery.transferVerifier != address(0),
      "TransferVerfier"
    );
    require(currentPool.periphery.keeper != address(0), "Keeper");
  }

  function _getCurrentPool(address pool)
    internal
    returns (StabilizedPool memory currentPool)
  {
    require(pool != address(0), "No addr(0)");
    currentPool = factory.getStabilizedPool(pool);
  }

  function _updateCurrentPool(address pool, StabilizedPool memory currentPool)
    internal
  {
    factory.setCurrentPool(pool, currentPool);
  }
}
