pragma solidity 0.8.11;

import "../libraries/uniswap/Babylonian.sol";
import "../libraries/uniswap/IUniswapV2Pair.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/RewardThrottleExtension.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../StabilizedPoolExtensions/DexHandlerExtension.sol";
import "../StabilizedPoolExtensions/AuctionExtension.sol";
import "../StabilizedPoolExtensions/SwingTraderManagerExtension.sol";
import "../StabilizedPoolExtensions/StabilizerNodeExtension.sol";
import "../interfaces/IKeeperCompatibleInterface.sol";
import "../interfaces/IMaltDataLab.sol";
import "../interfaces/IDexHandler.sol";
import "../interfaces/ITimekeeper.sol";
import "../interfaces/IDistributor.sol";
import "../interfaces/IRewardThrottle.sol";
import "../interfaces/IStabilizerNode.sol";
import "../interfaces/IMovingAverage.sol";
import "../interfaces/ISwingTrader.sol";

/// @title Pool Keeper
/// @author 0xScotch <scotch@malt.money>
/// @notice A chainlink keeper compatible contract to upkeep a Malt pool
contract UniV2PoolKeeper is
  StabilizedPoolUnit,
  AuctionExtension,
  IKeeperCompatibleInterface,
  RewardThrottleExtension,
  DataLabExtension,
  DexHandlerExtension,
  SwingTraderManagerExtension,
  StabilizerNodeExtension
{
  using SafeERC20 for ERC20;
  bytes32 public immutable KEEPER_ROLE;

  IVestingDistributor public vestingDistributor;
  ITimekeeper public timekeeper;

  bool public paused = true;
  bool public upkeepVesting = true;
  bool public upkeepStability = true;
  bool public upkeepTracking = true;

  address payable treasury;

  uint256 public minInterval = 10;
  uint256 internal lastTimestamp;
  uint256 internal lastUpdateMaltRatio;

  event SetMinInterval(uint256 interval);
  event SetUpkeepVesting(bool upkeepVesting);
  event SetUpkeepTracking(bool upkeepTracking);
  event SetUpkeepStability(bool upkeepStability);
  event SetMaltTimekeeper(address timekeeper);
  event SetVestingDistributor(address distributor);
  event SetPaused(bool paused);
  event UpdateTreasury(address treasury);

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    address keeperRegistry,
    address _timekeeper,
    address payable _treasury
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    KEEPER_ROLE = 0xfc8737ab85eb45125971625a9ebdb75cc78e01d5c1fa80c4c6e5203f47bc4fab;
    _grantRole(
      0xfc8737ab85eb45125971625a9ebdb75cc78e01d5c1fa80c4c6e5203f47bc4fab,
      keeperRegistry
    );

    timekeeper = ITimekeeper(_timekeeper);
    treasury = _treasury;
  }

  function setupContracts(
    address _maltDataLab,
    address _dexHandler,
    address _vestingDistributor,
    address _rewardThrottle,
    address pool,
    address _stabilizerNode,
    address _auction,
    address _swingTraderManager
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must be pool factory") {
    require(address(maltDataLab) == address(0), "Keeper: Already setup");
    require(_maltDataLab != address(0), "Keeper: MaltDataLab addr(0)");
    require(_dexHandler != address(0), "Keeper: DexHandler addr(0)");
    require(_rewardThrottle != address(0), "Keeper: RewardThrottle addr(0)");
    require(_vestingDistributor != address(0), "Keeper: VestinDist addr(0)");
    require(_stabilizerNode != address(0), "Keeper: StabNode addr(0)");
    require(_auction != address(0), "Keeper: Auction addr(0)");
    require(_swingTraderManager != address(0), "Keeper: Auction addr(0)");

    maltDataLab = IMaltDataLab(_maltDataLab);
    dexHandler = IDexHandler(_dexHandler);
    rewardThrottle = IRewardThrottle(_rewardThrottle);
    vestingDistributor = IVestingDistributor(_vestingDistributor);
    stabilizerNode = IStabilizerNode(_stabilizerNode);
    auction = IAuction(_auction);
    swingTraderManager = ISwingTrader(_swingTraderManager);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function checkUpkeep(
    bytes calldata /* checkData */
  )
    external
    view
    override
    returns (bool upkeepNeeded, bytes memory performData)
  {
    if (paused) {
      return (false, abi.encode(""));
    }
    uint256 currentEpoch = timekeeper.epoch();

    uint256 nextEpochStart = timekeeper.getEpochStartTime(currentEpoch + 1);

    bool shouldAdvance = block.timestamp >= nextEpochStart;

    (
      uint256 price,
      uint256 rootK,
      uint256 priceCumulative,
      uint256 blockTimestampLast
    ) = _getPoolState();

    uint256 swingTraderMaltRatio = swingTraderManager
      .calculateSwingTraderMaltRatio();

    IMovingAverage ratioMA = maltDataLab.ratioMA();
    uint256 sampleLength = ratioMA.sampleLength() / 2;

    performData = abi.encode(
      shouldAdvance,
      upkeepVesting,
      upkeepTracking,
      upkeepStability && _shouldAdjustSupply(price),
      (block.timestamp - lastUpdateMaltRatio) > sampleLength,
      price,
      rootK,
      priceCumulative,
      blockTimestampLast,
      swingTraderMaltRatio
    );
    upkeepNeeded = (block.timestamp - lastTimestamp) > minInterval;
  }

  function _shouldAdjustSupply(uint256 livePrice) internal view returns (bool) {
    bool stabilizeToPeg = stabilizerNode.onlyStabilizeToPeg();
    uint256 exchangeRate = maltDataLab.maltPriceAverage(
      stabilizerNode.priceAveragePeriod()
    );
    ERC20 collateralToken = ERC20(maltDataLab.collateralToken());
    uint256 decimals = collateralToken.decimals();
    uint256 pegPrice = maltDataLab.priceTarget();
    uint256 priceTarget = pegPrice;

    if (!stabilizeToPeg) {
      priceTarget = maltDataLab.getActualPriceTarget();
    }

    uint256 upperThreshold = (priceTarget *
      stabilizerNode.upperStabilityThresholdBps()) / 10000;
    uint256 lowerThreshold = (priceTarget *
      stabilizerNode.lowerStabilityThresholdBps()) / 10000;

    (uint256 livePrice, ) = dexHandler.maltMarketPrice();

    if (
      livePrice >=
      (pegPrice -
        (pegPrice * stabilizerNode.lowerStabilityThresholdBps()) /
        10000)
    ) {
      priceTarget = pegPrice;
    }

    uint256 currentAuctionId = auction.currentAuctionId();

    if (auction.isAuctionFinished(currentAuctionId)) {
      return true;
    }

    return ((exchangeRate <= (priceTarget - lowerThreshold) &&
      livePrice <= (priceTarget - lowerThreshold) &&
      !auction.auctionExists(currentAuctionId)) ||
      (exchangeRate >= (priceTarget + upperThreshold) &&
        livePrice >= (priceTarget + upperThreshold)));
  }

  function _getPoolState()
    internal
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    address collateralToken = maltDataLab.collateralToken();
    address malt = maltDataLab.malt();
    address stakeToken = maltDataLab.stakeToken();

    (
      uint256 reserve0,
      uint256 reserve1,
      uint32 blockTimestampLast
    ) = IUniswapV2Pair(stakeToken).getReserves();

    uint256 kLast = reserve0 * reserve1;
    uint256 rootK = Babylonian.sqrt(kLast);

    uint256 priceCumulative;

    if (malt < collateralToken) {
      priceCumulative = IUniswapV2Pair(stakeToken).price0CumulativeLast();
    } else {
      priceCumulative = IUniswapV2Pair(stakeToken).price1CumulativeLast();
    }

    (uint256 price, ) = dexHandler.maltMarketPrice();

    return (price, rootK, priceCumulative, blockTimestampLast);
  }

  function performUpkeep(bytes calldata performData)
    external
    onlyRoleMalt(KEEPER_ROLE, "Must have keeper role")
  {
    (
      bool shouldAdvance,
      bool shouldVest,
      bool shouldTrackPool,
      bool shouldStabilize,
      bool shouldTrackMaltRatio,
      uint256 price,
      uint256 rootK,
      uint256 priceCumulative,
      uint256 blockTimestampLast,
      uint256 swingTraderMaltRatio
    ) = abi.decode(
        performData,
        (
          bool,
          bool,
          bool,
          bool,
          bool,
          uint256,
          uint256,
          uint256,
          uint256,
          uint256
        )
      );

    if (shouldVest) {
      vestingDistributor.vest();
    }

    if (shouldTrackPool) {
      // This keeper should be whitelisted to make updates
      maltDataLab.trustedTrackPool(
        price,
        rootK,
        priceCumulative,
        blockTimestampLast
      );
    }

    if (shouldAdvance) {
      timekeeper.advance();
    }

    if (shouldStabilize) {
      try stabilizerNode.stabilize() {} catch (bytes memory error) {
        // do nothing if it fails
      }
    }

    if (shouldTrackMaltRatio) {
      maltDataLab.trustedTrackMaltRatio(swingTraderMaltRatio);
      lastUpdateMaltRatio = block.timestamp;
    }

    rewardThrottle.updateDesiredAPR();

    // send any proceeds to the treasury
    ERC20 collateralToken = ERC20(maltDataLab.collateralToken());
    uint256 balance = collateralToken.balanceOf(address(this));

    if (balance > 0) {
      collateralToken.safeTransfer(treasury, balance);
    }

    ERC20 malt = ERC20(maltDataLab.malt());
    balance = malt.balanceOf(address(this));

    if (balance > 0) {
      malt.safeTransfer(treasury, balance);
    }

    lastTimestamp = block.timestamp;
  }

  function setVestingDistributor(address _distributor)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_distributor != address(0), "Cannot use 0 address");
    vestingDistributor = IVestingDistributor(_distributor);
    emit SetVestingDistributor(_distributor);
  }

  function setTimekeeper(address _timekeeper)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role")
  {
    require(_timekeeper != address(0), "Cannot use 0 address");
    timekeeper = ITimekeeper(_timekeeper);
    emit SetMaltTimekeeper(_timekeeper);
  }

  function setMinInterval(uint256 _interval)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    minInterval = _interval;
    emit SetMinInterval(_interval);
  }

  function setUpkeepVesting(bool _upkeepVesting)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    upkeepVesting = _upkeepVesting;
    emit SetUpkeepVesting(_upkeepVesting);
  }

  function setUpkeepStability(bool _upkeepStability)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    upkeepStability = _upkeepStability;
    emit SetUpkeepStability(_upkeepStability);
  }

  function setUpkeepTracking(bool _upkeepTracking)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    upkeepTracking = _upkeepTracking;
    emit SetUpkeepTracking(_upkeepTracking);
  }

  function setTreasury(address payable _treasury)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role")
  {
    treasury = _treasury;
    emit UpdateTreasury(_treasury);
  }

  function togglePaused()
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    bool localPaused = paused;
    paused = !localPaused;
    emit SetPaused(localPaused);
  }

  function _accessControl()
    internal
    view
    override(
      RewardThrottleExtension,
      DataLabExtension,
      DexHandlerExtension,
      AuctionExtension,
      SwingTraderManagerExtension,
      StabilizerNodeExtension
    )
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
