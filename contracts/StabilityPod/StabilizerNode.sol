// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/security/Pausable.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/AuctionExtension.sol";
import "../StabilizedPoolExtensions/DexHandlerExtension.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../StabilizedPoolExtensions/ProfitDistributorExtension.sol";
import "../StabilizedPoolExtensions/SwingTraderManagerExtension.sol";
import "../StabilizedPoolExtensions/ImpliedCollateralServiceExtension.sol";
import "../interfaces/IAuction.sol";
import "../interfaces/IMaltDataLab.sol";
import "../interfaces/ITimekeeper.sol";
import "../interfaces/IRewardThrottle.sol";
import "../interfaces/IImpliedCollateralService.sol";
import "../interfaces/IDexHandler.sol";
import "../interfaces/ISwingTrader.sol";
import "../interfaces/IBurnMintableERC20.sol";
import "../interfaces/ISupplyDistributionController.sol";
import "../interfaces/IAuctionStartController.sol";
import "../interfaces/IProfitDistributor.sol";
import "../interfaces/IGlobalImpliedCollateralService.sol";

/// @title Stabilizer Node
/// @author 0xScotch <scotch@malt.money>
/// @notice The backbone of the Malt stability system. In charge of triggering actions to stabilize price
contract StabilizerNode is
  StabilizedPoolUnit,
  AuctionExtension,
  DexHandlerExtension,
  DataLabExtension,
  ProfitDistributorExtension,
  SwingTraderManagerExtension,
  ImpliedCollateralServiceExtension,
  Pausable
{
  using SafeERC20 for ERC20;

  uint256 internal stabilizeWindowEnd;
  uint256 public stabilizeBackoffPeriod = 5 * 60; // 5 minutes
  uint256 public upperStabilityThresholdBps = 100; // 1%
  uint256 public lowerStabilityThresholdBps = 100;
  uint256 public priceAveragePeriod = 5 minutes;
  uint256 public fastAveragePeriod = 30; // 30 seconds
  uint256 public overrideDistanceBps = 200; // 2%
  uint256 public callerRewardCutBps = 30; // 0.3%

  uint256 public expansionDampingFactor = 1;

  uint256 public defaultIncentive = 100; // in Malt
  uint256 public trackingIncentive = 20; // in 100ths of a Malt

  uint256 public upperBandLimitBps = 100000; // 1000%
  uint256 public lowerBandLimitBps = 1000; // 10%
  uint256 public sampleSlippageBps = 2000; // 20%
  uint256 public skipAuctionThreshold;
  uint256 public preferAuctionThreshold;

  uint256 public lastStabilize;
  uint256 public lastTracking;
  uint256 public trackingBackoff = 30; // 30 seconds
  uint256 public primedBlock;
  uint256 public primedWindow = 10; // blocks

  bool internal trackAfterStabilize = true;
  bool public onlyStabilizeToPeg = false;
  bool public usePrimedWindow;

  address public supplyDistributionController;
  address public auctionStartController;

  event MintMalt(uint256 amount);
  event Stabilize(uint256 timestamp, uint256 exchangeRate);
  event SetStabilizeBackoff(uint256 period);
  event SetDefaultIncentive(uint256 incentive);
  event SetTrackingIncentive(uint256 incentive);
  event SetExpansionDamping(uint256 amount);
  event SetPriceAveragePeriod(uint256 period);
  event SetOverrideDistance(uint256 distance);
  event SetFastAveragePeriod(uint256 period);
  event SetStabilityThresholds(uint256 upper, uint256 lower);
  event SetSupplyDistributionController(address _controller);
  event SetAuctionStartController(address _controller);
  event SetBandLimits(uint256 _upper, uint256 _lower);
  event SetSlippageBps(uint256 _slippageBps);
  event SetSkipAuctionThreshold(uint256 _skipAuctionThreshold);
  event SetEmergencyMintThresholdBps(uint256 thresholdBps);
  event Tracking();
  event SetTrackingBackoff(uint256 backoff);
  event SetCallerCut(uint256 callerCutBps);
  event SetPreferAuctionThreshold(uint256 preferAuctionThreshold);
  event SetTrackAfterStabilize(bool track);
  event SetOnlyStabilizeToPeg(bool stabilize);
  event SetPrimedWindow(uint256 primedWindow);
  event SetUsePrimedWindow(bool usePrimedWindow);

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    uint256 _skipAuctionThreshold,
    uint256 _preferAuctionThreshold
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    skipAuctionThreshold = _skipAuctionThreshold;
    preferAuctionThreshold = _preferAuctionThreshold;

    lastStabilize = block.timestamp;
  }

  function setupContracts(
    address _malt,
    address _collateralToken,
    address _dexHandler,
    address _maltDataLab,
    address _impliedCollateralService,
    address _auction,
    address _swingTraderManager,
    address _profitDistributor,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role") {
    require(!contractActive, "StabilizerNode: Already setup");
    require(_malt != address(0), "StabilizerNode: Malt addr(0)");
    require(_collateralToken != address(0), "StabilizerNode: Col addr(0)");
    require(_dexHandler != address(0), "StabilizerNode: DexHandler addr(0)");
    require(_maltDataLab != address(0), "StabilizerNode: DataLab addr(0)");
    require(
      _swingTraderManager != address(0),
      "StabilizerNode: Swing Manager addr(0)"
    );
    require(
      _impliedCollateralService != address(0),
      "StabilizerNode: ImpCol addr(0)"
    );
    require(_auction != address(0), "StabilizerNode: Auction addr(0)");
    require(
      _profitDistributor != address(0),
      "StabilizerNode: ProfitDistributor addr(0)"
    );

    contractActive = true;

    collateralToken = ERC20(_collateralToken);
    malt = IBurnMintableERC20(_malt);
    dexHandler = IDexHandler(_dexHandler);
    maltDataLab = IMaltDataLab(_maltDataLab);
    swingTraderManager = ISwingTrader(_swingTraderManager);
    impliedCollateralService = IImpliedCollateralService(
      _impliedCollateralService
    );
    auction = IAuction(_auction);
    profitDistributor = IProfitDistributor(_profitDistributor);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function stabilize() external nonReentrant onlyEOA onlyActive whenNotPaused {
    // Ensure data consistency
    maltDataLab.trackPool();

    // Finalize auction if possible before potentially starting a new one
    auction.checkAuctionFinalization();

    require(
      block.timestamp >= stabilizeWindowEnd || _stabilityWindowOverride(),
      "Can't call stabilize"
    );
    stabilizeWindowEnd = block.timestamp + stabilizeBackoffPeriod;

    // used in 3 location.
    uint256 exchangeRate = maltDataLab.maltPriceAverage(priceAveragePeriod);
    bool stabilizeToPeg = onlyStabilizeToPeg; // gas

    if (!_shouldAdjustSupply(exchangeRate, stabilizeToPeg)) {
      lastStabilize = block.timestamp;
      impliedCollateralService.syncGlobalCollateral();
      return;
    }

    emit Stabilize(block.timestamp, exchangeRate);

    (uint256 livePrice, ) = dexHandler.maltMarketPrice();

    uint256 priceTarget = maltDataLab.getActualPriceTarget();
    // The upper and lower bands here avoid any issues with price
    // descrepency between the TWAP and live market price.
    // This avoids starting auctions too quickly into a big selloff
    // and also reduces risk of flashloan vectors
    address sender = _msgSender();
    if (exchangeRate > priceTarget) {
      if (
        !hasRole(ADMIN_ROLE, sender) &&
        !hasRole(INTERNAL_WHITELIST_ROLE, sender)
      ) {
        uint256 upperBand = exchangeRate +
          ((exchangeRate * upperBandLimitBps) / 10000);
        uint256 latestSample = maltDataLab.maltPriceAverage(0);
        uint256 minThreshold = latestSample -
          (((latestSample - priceTarget) * sampleSlippageBps) / 10000);

        require(livePrice < upperBand, "Stabilize: Beyond upper bound");
        require(livePrice > minThreshold, "Stabilize: Slippage threshold");
      }

      _distributeSupply(livePrice, priceTarget, stabilizeToPeg);
    } else {
      if (
        !hasRole(ADMIN_ROLE, sender) &&
        !hasRole(INTERNAL_WHITELIST_ROLE, sender)
      ) {
        uint256 lowerBand = exchangeRate -
          ((exchangeRate * lowerBandLimitBps) / 10000);
        require(livePrice > lowerBand, "Stabilize: Beyond lower bound");
      }

      uint256 stEntryPrice = maltDataLab.getSwingTraderEntryPrice();
      if (exchangeRate <= stEntryPrice) {
        if (_validateSwingTraderTrigger(livePrice, stEntryPrice)) {
          // Reset primedBlock
          primedBlock = 0;
          _triggerSwingTrader(priceTarget, livePrice);
        }
      } else {
        _startAuction(priceTarget);
      }
    }

    if (trackAfterStabilize) {
      maltDataLab.trackPool();
    }
    impliedCollateralService.syncGlobalCollateral();
    lastStabilize = block.timestamp;
  }

  function endAuctionEarly() external onlyActive whenNotPaused {
    // This call reverts if the auction isn't ended
    auction.endAuctionEarly();

    // It hasn't reverted so the auction was ended. Pay the incentive
    malt.mint(msg.sender, defaultIncentive * (10**malt.decimals()));
    emit MintMalt(defaultIncentive * (10**malt.decimals()));
  }

  function trackPool() external onlyActive {
    require(block.timestamp >= lastTracking + trackingBackoff, "Too early");
    bool success = maltDataLab.trackPool();
    require(success, "Too early");
    malt.mint(msg.sender, (trackingIncentive * (10**malt.decimals())) / 100); // div 100 because units are cents
    lastTracking = block.timestamp;
    emit Tracking();
  }

  function primedWindowData() public view returns (bool, uint256) {
    return (usePrimedWindow, primedBlock + primedWindow);
  }

  /*
   * INTERNAL VIEW FUNCTIONS
   */
  function _stabilityWindowOverride() internal view returns (bool) {
    address sender = _msgSender();
    if (
      hasRole(ADMIN_ROLE, sender) || hasRole(INTERNAL_WHITELIST_ROLE, sender)
    ) {
      // Admin can always stabilize
      return true;
    }
    // Must have elapsed at least one period of the moving average before we stabilize again
    if (block.timestamp < lastStabilize + fastAveragePeriod) {
      return false;
    }

    uint256 priceTarget = maltDataLab.getActualPriceTarget();
    uint256 exchangeRate = maltDataLab.maltPriceAverage(fastAveragePeriod);

    uint256 upperThreshold = (priceTarget * (10000 + overrideDistanceBps)) /
      10000;

    return exchangeRate >= upperThreshold;
  }

  function _shouldAdjustSupply(uint256 exchangeRate, bool stabilizeToPeg)
    internal
    view
    returns (bool)
  {
    uint256 decimals = collateralToken.decimals();
    uint256 priceTarget;

    if (stabilizeToPeg) {
      priceTarget = maltDataLab.priceTarget();
    } else {
      priceTarget = maltDataLab.getActualPriceTarget();
    }

    uint256 upperThreshold = (priceTarget * upperStabilityThresholdBps) / 10000;
    uint256 lowerThreshold = (priceTarget * lowerStabilityThresholdBps) / 10000;

    return
      (exchangeRate <= (priceTarget - lowerThreshold) &&
        !auction.auctionExists(auction.currentAuctionId())) ||
      exchangeRate >= (priceTarget + upperThreshold);
  }

  /*
   * INTERNAL FUNCTIONS
   */
  function _validateSwingTraderTrigger(uint256 livePrice, uint256 entryPrice)
    internal
    returns (bool)
  {
    if (usePrimedWindow) {
      if (livePrice > entryPrice) {
        return false;
      }

      if (block.number > primedBlock + primedWindow) {
        primedBlock = block.number;
        malt.mint(msg.sender, defaultIncentive * (10**malt.decimals()));
        emit MintMalt(defaultIncentive * (10**malt.decimals()));
        return false;
      }

      if (primedBlock == block.number) {
        return false;
      }
    }

    return true;
  }

  function _triggerSwingTrader(uint256 priceTarget, uint256 exchangeRate)
    internal
  {
    uint256 decimals = collateralToken.decimals();
    uint256 unity = 10**decimals;
    IGlobalImpliedCollateralService globalIC = maltDataLab.globalIC();
    uint256 icTotal = maltDataLab.maltToRewardDecimals(
      globalIC.collateralRatio()
    );

    if (icTotal >= unity) {
      icTotal = unity;
    }

    uint256 originalPriceTarget = priceTarget;

    // TODO StabilizerNode.sol these checks won't work when working with pools not pegged to 1 Wed 26 Oct 2022 16:40:25 BST
    if (exchangeRate < icTotal) {
      priceTarget = icTotal;
    }

    uint256 purchaseAmount = dexHandler.calculateBurningTradeSize(priceTarget);

    if (purchaseAmount > preferAuctionThreshold) {
      uint256 capitalUsed = swingTraderManager.buyMalt(purchaseAmount);

      uint256 callerCut = (capitalUsed * callerRewardCutBps) / 10000;

      if (callerCut != 0) {
        malt.mint(msg.sender, callerCut);
        emit MintMalt(callerCut);
      }
    } else {
      _startAuction(originalPriceTarget);
    }
  }

  function _distributeSupply(
    uint256 livePrice,
    uint256 priceTarget,
    bool stabilizeToPeg
  ) internal {
    if (supplyDistributionController != address(0)) {
      bool success = ISupplyDistributionController(supplyDistributionController)
        .check();
      if (!success) {
        return;
      }
    }

    uint256 pegPrice = maltDataLab.priceTarget();

    uint256 lowerThreshold = (pegPrice * lowerStabilityThresholdBps) / 10000;
    if (stabilizeToPeg || livePrice >= pegPrice - lowerThreshold) {
      priceTarget = pegPrice;
    }

    uint256 tradeSize = dexHandler.calculateMintingTradeSize(priceTarget) /
      expansionDampingFactor;

    if (tradeSize == 0) {
      return;
    }

    uint256 swingAmount = swingTraderManager.sellMalt(tradeSize);

    if (swingAmount >= tradeSize) {
      return;
    }

    tradeSize = tradeSize - swingAmount;

    malt.mint(address(dexHandler), tradeSize);
    emit MintMalt(tradeSize);
    // Transfer verification ensure any attempt to
    // sandwhich will trigger stabilize first
    uint256 rewards = dexHandler.sellMalt(tradeSize, 10000);

    uint256 callerCut = (rewards * callerRewardCutBps) / 10000;

    if (callerCut != 0) {
      rewards -= callerCut;
      collateralToken.safeTransfer(msg.sender, callerCut);
    }

    collateralToken.safeTransfer(address(profitDistributor), rewards);

    profitDistributor.handleProfit(rewards);
  }

  function _startAuction(uint256 priceTarget) internal {
    if (auctionStartController != address(0)) {
      bool success = IAuctionStartController(auctionStartController)
        .checkForStart();
      if (!success) {
        return;
      }
    }

    uint256 purchaseAmount = dexHandler.calculateBurningTradeSize(priceTarget);

    if (purchaseAmount < skipAuctionThreshold) {
      return;
    }

    // TODO StabilizerNode.sol invert priceTarget? Fri 21 Oct 2022 11:02:43 BST
    bool success = auction.triggerAuction(priceTarget, purchaseAmount);

    if (success) {
      malt.mint(msg.sender, defaultIncentive * (10**malt.decimals()));
      emit MintMalt(defaultIncentive * (10**malt.decimals()));
    }
  }

  /*
   * PRIVILEDGED FUNCTIONS
   */

  function setStabilizeBackoff(uint256 _period)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_period > 0, "Must be greater than 0");
    stabilizeBackoffPeriod = _period;
    emit SetStabilizeBackoff(_period);
  }

  function setDefaultIncentive(uint256 _incentive)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_incentive != 0 && _incentive <= 1000, "Incentive out of range");

    defaultIncentive = _incentive;

    emit SetDefaultIncentive(_incentive);
  }

  function setTrackingIncentive(uint256 _incentive)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    // Priced in cents. Must be less than 1000 Malt
    require(_incentive != 0 && _incentive <= 100000, "Incentive out of range");

    trackingIncentive = _incentive;

    emit SetTrackingIncentive(_incentive);
  }

  /// @notice Only callable by Admin address.
  /// @dev Sets the Expansion Damping units.
  /// @param amount: Amount to set Expansion Damping units to.
  function setExpansionDamping(uint256 amount)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(amount > 0, "No negative damping");

    expansionDampingFactor = amount;
    emit SetExpansionDamping(amount);
  }

  function setStabilityThresholds(uint256 _upper, uint256 _lower)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_upper != 0 && _lower != 0, "Must be above 0");
    require(_lower < 10000, "Lower to large");

    upperStabilityThresholdBps = _upper;
    lowerStabilityThresholdBps = _lower;
    emit SetStabilityThresholds(_upper, _lower);
  }

  function setSupplyDistributionController(address _controller)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    // This is allowed to be set to address(0) as its checked before calling methods on it
    supplyDistributionController = _controller;
    emit SetSupplyDistributionController(_controller);
  }

  function setAuctionStartController(address _controller)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    // This is allowed to be set to address(0) as its checked before calling methods on it
    auctionStartController = _controller;
    emit SetAuctionStartController(_controller);
  }

  function setPriceAveragePeriod(uint256 _period)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_period > 0, "Cannot have 0 period");
    priceAveragePeriod = _period;
    emit SetPriceAveragePeriod(_period);
  }

  function setOverrideDistance(uint256 _distance)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(
      _distance != 0 && _distance < 10000,
      "Override must be between 0-100%"
    );
    overrideDistanceBps = _distance;
    emit SetOverrideDistance(_distance);
  }

  function setFastAveragePeriod(uint256 _period)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_period > 0, "Cannot have 0 period");
    fastAveragePeriod = _period;
    emit SetFastAveragePeriod(_period);
  }

  function setBandLimits(uint256 _upper, uint256 _lower)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_upper != 0 && _lower != 0, "Cannot have 0 band limit");
    upperBandLimitBps = _upper;
    lowerBandLimitBps = _lower;
    emit SetBandLimits(_upper, _lower);
  }

  function setSlippageBps(uint256 _slippageBps)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_slippageBps <= 10000, "slippage: Must be <= 100%");
    sampleSlippageBps = _slippageBps;
    emit SetSlippageBps(_slippageBps);
  }

  function setSkipAuctionThreshold(uint256 _skipAuctionThreshold)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    skipAuctionThreshold = _skipAuctionThreshold;
    emit SetSkipAuctionThreshold(_skipAuctionThreshold);
  }

  function setPreferAuctionThreshold(uint256 _preferAuctionThreshold)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    preferAuctionThreshold = _preferAuctionThreshold;
    emit SetPreferAuctionThreshold(_preferAuctionThreshold);
  }

  function setTrackingBackoff(uint256 _backoff)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_backoff != 0, "Cannot be 0");
    trackingBackoff = _backoff;
    emit SetTrackingBackoff(_backoff);
  }

  function setTrackAfterStabilize(bool _track)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    trackAfterStabilize = _track;
    emit SetTrackAfterStabilize(_track);
  }

  function setOnlyStabilizeToPeg(bool _stabilize)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    onlyStabilizeToPeg = _stabilize;
    emit SetOnlyStabilizeToPeg(_stabilize);
  }

  function setCallerCut(uint256 _callerCut)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_callerCut <= 1000, "Must be less than 10%");
    callerRewardCutBps = _callerCut;
    emit SetCallerCut(_callerCut);
  }

  function togglePause()
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  function setPrimedWindow(uint256 _primedWindow)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_primedWindow != 0, "Cannot be 0");
    primedWindow = _primedWindow;
    emit SetPrimedWindow(_primedWindow);
  }

  function setUsePrimedWindow(bool _usePrimedWindow)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    usePrimedWindow = _usePrimedWindow;
    emit SetUsePrimedWindow(_usePrimedWindow);
  }

  function _accessControl()
    internal
    override(
      AuctionExtension,
      DexHandlerExtension,
      DataLabExtension,
      ProfitDistributorExtension,
      SwingTraderManagerExtension,
      ImpliedCollateralServiceExtension
    )
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
