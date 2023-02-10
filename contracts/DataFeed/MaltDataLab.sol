// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";

import "../interfaces/IDualMovingAverage.sol";
import "../interfaces/IMovingAverage.sol";
import "../interfaces/IBurnMintableERC20.sol";
import "../interfaces/IImpliedCollateralService.sol";
import "../interfaces/IGlobalImpliedCollateralService.sol";
import "../interfaces/ISwingTrader.sol";

import "../libraries/uniswap/IUniswapV2Pair.sol";
import "../libraries/SafeBurnMintableERC20.sol";
import "../libraries/uniswap/FixedPoint.sol";
import "../libraries/ABDKMath64x64.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/ImpliedCollateralServiceExtension.sol";
import "../StabilizedPoolExtensions/SwingTraderManagerExtension.sol";
import "../StabilizedPoolExtensions/GlobalICExtension.sol";

/// @title Malt Data Lab
/// @author 0xScotch <scotch@malt.money>
/// @notice The central source of all of Malt protocol's internal data needs
/// @dev Over time usage of MovingAverage will likely be replaced with more reliable oracles
contract MaltDataLab is
  StabilizedPoolUnit,
  ImpliedCollateralServiceExtension,
  SwingTraderManagerExtension,
  GlobalICExtension
{
  using FixedPoint for *;
  using ABDKMath64x64 for *;
  using SafeBurnMintableERC20 for IBurnMintableERC20;

  bytes32 public immutable UPDATER_ROLE;

  // The dual values will be the pool price and the square root of the invariant k
  IDualMovingAverage public poolMA;
  IMovingAverage public ratioMA;

  uint256 public priceTarget = 10**18; // $1
  uint256 public maltPriceLookback = 10 minutes;
  uint256 public reserveLookback = 15 minutes;
  uint256 public kLookback = 30 minutes;
  uint256 public maltRatioLookback = 4 hours;

  uint256 public z = 20;
  uint256 public swingTraderLowBps = 1000; // 10%
  uint256 public auctionLowBps = 7000; // 70%
  uint256 public breakpointBps = 5000; // 50%

  uint256 public maltPriceCumulativeLast;
  uint256 public maltPriceTimestampLast;

  event TrackPool(uint256 price, uint256 rootK);

  constructor(
    address timelock,
    address repository,
    address poolFactory
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    UPDATER_ROLE = 0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab;
  }

  function setupContracts(
    address _malt,
    address _collateralToken,
    address _stakeToken,
    address _poolMA,
    address _ratioMA,
    address _impliedCollateralService,
    address _swingTraderManager,
    address _globalIC,
    address _trustedUpdater
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must be pool factory") {
    require(!contractActive, "MaltDataLab: Already setup");
    require(_malt != address(0), "MaltDataLab: Malt addr(0)");
    require(_collateralToken != address(0), "MaltDataLab: Col addr(0)");
    require(_stakeToken != address(0), "MaltDataLab: LP Token addr(0)");
    require(_poolMA != address(0), "MaltDataLab: PoolMA addr(0)");
    require(
      _impliedCollateralService != address(0),
      "MaltDataLab: ImpColSvc addr(0)"
    );
    require(
      _swingTraderManager != address(0),
      "MaltDataLab: STManager addr(0)"
    );
    require(_globalIC != address(0), "MaltDataLab: GlobalIC addr(0)");
    require(_ratioMA != address(0), "MaltDataLab: RatioMA addr(0)");

    contractActive = true;

    _roleSetup(UPDATER_ROLE, _trustedUpdater);

    malt = IBurnMintableERC20(_malt);
    collateralToken = ERC20(_collateralToken);
    stakeToken = IUniswapV2Pair(_stakeToken);
    poolMA = IDualMovingAverage(_poolMA);
    impliedCollateralService = IImpliedCollateralService(
      _impliedCollateralService
    );
    swingTraderManager = ISwingTrader(_swingTraderManager);
    globalIC = IGlobalImpliedCollateralService(_globalIC);
    ratioMA = IMovingAverage(_ratioMA);

    (, address updater, ) = poolFactory.getPool(_stakeToken);
    _setPoolUpdater(updater);
  }

  function smoothedMaltPrice() public view returns (uint256 price) {
    (price, ) = poolMA.getValueWithLookback(maltPriceLookback);
  }

  function smoothedK() public view returns (uint256) {
    (, uint256 rootK) = poolMA.getValueWithLookback(kLookback);
    return rootK * rootK;
  }

  function smoothedReserves()
    public
    view
    returns (uint256 maltReserves, uint256 collateralReserves)
  {
    // Malt reserves = sqrt(k / malt price)
    (uint256 price, uint256 rootK) = poolMA.getValueWithLookback(
      reserveLookback
    );
    uint256 unity = 10**collateralToken.decimals();

    // maltReserves = sqrt(k * 1 / price);
    maltReserves = Babylonian.sqrt((rootK * rootK * unity) / price);
    collateralReserves = (maltReserves * price) / unity;
  }

  function smoothedMaltRatio() public view returns (uint256) {
    return ratioMA.getValueWithLookback(maltRatioLookback);
  }

  function maltPriceAverage(uint256 _lookback)
    public
    view
    returns (uint256 price)
  {
    (price, ) = poolMA.getValueWithLookback(_lookback);
  }

  function kAverage(uint256 _lookback) public view returns (uint256) {
    (, uint256 rootK) = poolMA.getValueWithLookback(_lookback);
    return rootK * rootK;
  }

  function poolReservesAverage(uint256 _lookback)
    public
    view
    returns (uint256 maltReserves, uint256 collateralReserves)
  {
    // Malt reserves = sqrt(k / malt price)
    (uint256 price, uint256 rootK) = poolMA.getValueWithLookback(_lookback);

    uint256 unity = 10**collateralToken.decimals();

    // maltReserves = sqrt(k * 1 / price);
    maltReserves = Babylonian.sqrt((rootK * rootK * unity) / price);
    collateralReserves = (maltReserves * price) / unity;
  }

  function lastMaltPrice()
    public
    view
    returns (uint256 price, uint64 timestamp)
  {
    (timestamp, , , , , price, ) = poolMA.getLiveSample();
  }

  function lastPoolReserves()
    public
    view
    returns (
      uint256 maltReserves,
      uint256 collateralReserves,
      uint64 timestamp
    )
  {
    // Malt reserves = sqrt(k / malt price)
    (uint64 timestamp, , , , , uint256 price, uint256 rootK) = poolMA
      .getLiveSample();

    uint256 unity = 10**collateralToken.decimals();

    // maltReserves = sqrt(k * 1 / price);
    maltReserves = Babylonian.sqrt((rootK * rootK * unity) / price);
    collateralReserves = (maltReserves * price) / unity;
  }

  function lastK() public view returns (uint256 kLast, uint64 timestamp) {
    // Malt reserves = sqrt(k / malt price)
    (uint64 timestamp, , , , , , uint256 rootK) = poolMA.getLiveSample();

    kLast = rootK * rootK;
  }

  function realValueOfLPToken(uint256 amount) external view returns (uint256) {
    (uint256 maltPrice, uint256 rootK) = poolMA.getValueWithLookback(
      reserveLookback
    );

    uint256 unity = 10**collateralToken.decimals();

    // TODO MaltDataLab.sol will this work with other decimals? Sat 22 Oct 2022 18:44:07 BST

    // maltReserves = sqrt(k * 1 / price);
    uint256 maltReserves = Babylonian.sqrt((rootK * rootK * unity) / maltPrice);
    uint256 collateralReserves = (maltReserves * maltPrice) / unity;

    if (maltReserves == 0) {
      return 0;
    }

    uint256 totalLPSupply = stakeToken.totalSupply();

    uint256 maltValue = (amount * maltReserves) / totalLPSupply;
    uint256 rewardValue = (amount * collateralReserves) / totalLPSupply;

    return rewardValue + ((maltValue * maltPrice) / unity);
  }

  function getRealBurnBudget(uint256 maxBurnSpend, uint256 premiumExcess)
    external
    view
    returns (uint256)
  {
    if (maxBurnSpend > premiumExcess) {
      uint256 diff = maxBurnSpend - premiumExcess;

      int128 stMaltRatioInt = ABDKMath64x64
        .fromUInt(swingTraderManager.calculateSwingTraderMaltRatio())
        .div(ABDKMath64x64.fromUInt(10**collateralToken.decimals()))
        .mul(ABDKMath64x64.fromUInt(100));
      int128 purchaseParityInt = ABDKMath64x64.fromUInt(z);

      if (stMaltRatioInt > purchaseParityInt) {
        return maxBurnSpend;
      }

      uint256 bps = stMaltRatioInt
        .div(purchaseParityInt)
        .mul(ABDKMath64x64.fromUInt(10000))
        .toUInt();
      uint256 additional = (diff * bps) / 10000;

      return premiumExcess + additional;
    }

    return maxBurnSpend;
  }

  function maltToRewardDecimals(uint256 maltAmount)
    public
    view
    returns (uint256)
  {
    uint256 rewardDecimals = collateralToken.decimals();
    uint256 maltDecimals = malt.decimals();

    if (rewardDecimals == maltDecimals) {
      return maltAmount;
    } else if (rewardDecimals > maltDecimals) {
      uint256 diff = rewardDecimals - maltDecimals;
      return maltAmount * (10**diff);
    } else {
      uint256 diff = maltDecimals - rewardDecimals;
      return maltAmount / (10**diff);
    }
  }

  function rewardToMaltDecimals(uint256 amount) public view returns (uint256) {
    uint256 rewardDecimals = collateralToken.decimals();
    uint256 maltDecimals = malt.decimals();

    if (rewardDecimals == maltDecimals) {
      return amount;
    } else if (rewardDecimals > maltDecimals) {
      uint256 diff = rewardDecimals - maltDecimals;
      return amount / (10**diff);
    } else {
      uint256 diff = maltDecimals - rewardDecimals;
      return amount * (10**diff);
    }
  }

  /*
   * Public mutation methods
   */
  function trackPool() external onlyActive returns (bool) {
    (uint256 reserve0, uint256 reserve1, uint32 blockTimestampLast) = stakeToken
      .getReserves();

    if (blockTimestampLast < maltPriceTimestampLast) {
      // stale data
      return false;
    }

    uint256 kLast = reserve0 * reserve1;

    uint256 rootK = Babylonian.sqrt(kLast);

    uint256 price;
    uint256 priceCumulative;

    if (address(malt) < address(collateralToken)) {
      priceCumulative = stakeToken.price0CumulativeLast();
    } else {
      priceCumulative = stakeToken.price1CumulativeLast();
    }

    if (
      blockTimestampLast > maltPriceTimestampLast &&
      maltPriceCumulativeLast != 0
    ) {
      price = FixedPoint
        .uq112x112(
          uint224(
            (priceCumulative - maltPriceCumulativeLast) /
              (blockTimestampLast - maltPriceTimestampLast)
          )
        )
        .mul(priceTarget)
        .decode144();
    } else if (
      maltPriceCumulativeLast > 0 && priceCumulative == maltPriceCumulativeLast
    ) {
      (, , , , , price, ) = poolMA.getLiveSample();
    }

    if (price != 0) {
      // Use rootK to slow down growth of cumulativeValue
      poolMA.update(price, rootK);
      emit TrackPool(price, rootK);
    }

    maltPriceCumulativeLast = priceCumulative;
    maltPriceTimestampLast = blockTimestampLast;

    return true;
  }

  function getSwingTraderEntryPrice()
    external
    view
    returns (uint256 stEntryPrice)
  {
    /*
     * Note that in this method there are two separate units in play
     *
     * 1. Values from other contracts are uint256 denominated in collateralToken.decimals()
     * 2. int128 values are ABDKMath64x64 values. These can be thought of as regular decimals
     *
     * This means that all the values denominated in collateralToken.decimals need to be divided by
     * that decimal value to turn them into "real" decimals. This is why the conversion between
     * the two always contains a "unityInt" value (either division when going to 64x64 and
     * multiplication when going to collateralToken.decimal() value)
     */

    /*
     * Get all the values we need
     */
    uint256 unity = 10**collateralToken.decimals();
    uint256 icTotal = maltToRewardDecimals(globalIC.collateralRatio());

    if (icTotal >= unity) {
      // No need to do math here. Just return priceTarget
      return priceTarget;
    }

    uint256 stMaltRatio = swingTraderManager.calculateSwingTraderMaltRatio();
    uint256 swingTraderBottomPrice = (icTotal * (10000 - swingTraderLowBps)) /
      10000;

    /*
     * Convert all to 64x64
     */
    int128 unityInt = ABDKMath64x64.fromUInt(unity);
    int128 icTotalInt = ABDKMath64x64.fromUInt(icTotal).div(unityInt);
    int128 stMaltRatioInt = ABDKMath64x64
      .fromUInt(stMaltRatio)
      .div(unityInt)
      .mul(ABDKMath64x64.fromUInt(100));
    int128 oneInt = ABDKMath64x64.fromUInt(1);
    int128 swingTraderBottomPriceInt = ABDKMath64x64
      .fromUInt(swingTraderBottomPrice)
      .div(unityInt);

    /*
     * Do all the math (all these values are in 64x64)
     */
    int128 decayRate;
    {
      // to avoid stack to deep error

      int128 lnSwingTraderBottomDelta = ABDKMath64x64.ln(
        icTotalInt.sub(swingTraderBottomPriceInt)
      );
      int128 lnTradingHeadroom = ABDKMath64x64.ln(
        oneInt.sub(swingTraderBottomPriceInt)
      );
      int128 purchaseParityInt = ABDKMath64x64.fromUInt(z);
      decayRate = ABDKMath64x64.div(
        lnSwingTraderBottomDelta.sub(lnTradingHeadroom),
        purchaseParityInt
      );
    }

    int128 cooefficient = ABDKMath64x64.sub(oneInt, swingTraderBottomPriceInt);
    int128 exponent = decayRate.mul(stMaltRatioInt);

    int128 stEntryPriceInt = cooefficient.mul(ABDKMath64x64.exp(exponent)).add(
      swingTraderBottomPriceInt
    );

    // Convert back to collateralToken.decimals and return the value
    return stEntryPriceInt.mul(ABDKMath64x64.fromUInt(priceTarget)).toUInt();
  }

  function getActualPriceTarget() external view returns (uint256) {
    uint256 unity = 10**collateralToken.decimals();
    uint256 icTotal = maltToRewardDecimals(globalIC.collateralRatio());

    if (icTotal > unity) {
      icTotal = unity;
    }

    /*
     * Convert all to 64x64
     */
    int128 unityInt = ABDKMath64x64.fromUInt(unity);
    int128 icTotalInt = ABDKMath64x64.fromUInt(icTotal).div(unityInt);
    int128 stMaltRatioInt = ABDKMath64x64
      .fromUInt(smoothedMaltRatio())
      .div(unityInt)
      .mul(ABDKMath64x64.fromUInt(100));
    int128 purchaseParityInt = ABDKMath64x64.fromUInt(z);
    int128 breakpointInt = ABDKMath64x64.div(
      ABDKMath64x64.mul(
        purchaseParityInt,
        ABDKMath64x64.fromUInt(breakpointBps)
      ),
      ABDKMath64x64.fromUInt(10000)
    );
    int128 oneInt = ABDKMath64x64.fromUInt(1);

    int128 m = (icTotalInt.sub(oneInt)).div(
      purchaseParityInt.sub(breakpointInt)
    );

    int128 actualTarget64 = (
      oneInt.add(m.mul(stMaltRatioInt)).sub(m.mul(breakpointInt))
    );

    uint256 localTarget = priceTarget; // gas

    if (actualTarget64.toInt() < 0) {
      return (icTotal * localTarget) / unity;
    }

    uint256 actualTarget = actualTarget64.mul(unityInt).toUInt();
    uint256 normActualTarget = (actualTarget * localTarget) / unity;

    if (normActualTarget > localTarget) {
      return localTarget;
    } else if (actualTarget < icTotal && icTotal < localTarget) {
      return (icTotal * localTarget) / unity;
    }

    return normActualTarget;
  }

  function trackSwingTraderMaltRatio() external {
    uint256 maltRatio = swingTraderManager.calculateSwingTraderMaltRatio();
    ratioMA.update(maltRatio);
  }

  /*
   * PRIVILEDGED METHODS
   */
  function trustedTrackPool(
    uint256 price,
    uint256 rootK,
    uint256 priceCumulative,
    uint256 blockTimestampLast
  ) external onlyRoleMalt(UPDATER_ROLE, "Must have updater role") {
    require(
      priceCumulative >= maltPriceCumulativeLast,
      "trustedTrackPool: priceCumulative"
    );

    if (price != 0) {
      poolMA.update(price, rootK);
      emit TrackPool(price, rootK);
    }

    maltPriceCumulativeLast = priceCumulative;
    maltPriceTimestampLast = blockTimestampLast;
  }

  function trustedTrackMaltRatio(uint256 maltRatio)
    external
    onlyRoleMalt(UPDATER_ROLE, "Must have updater role")
  {
    ratioMA.update(maltRatio);
  }

  function setPriceTarget(uint256 _price)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_price > 0, "Cannot have 0 price");
    _setPriceTarget(_price);
  }

  // This will get used when price target is set dynamically via external oracle
  function _setPriceTarget(uint256 _price) internal {
    priceTarget = _price;
    impliedCollateralService.syncGlobalCollateral();
  }

  function setMaltPriceLookback(uint256 _lookback)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_lookback > 0, "Cannot have 0 lookback");
    maltPriceLookback = _lookback;
  }

  function setReserveLookback(uint256 _lookback)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_lookback > 0, "Cannot have 0 lookback");
    reserveLookback = _lookback;
  }

  function setKLookback(uint256 _lookback)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_lookback > 0, "Cannot have 0 lookback");
    kLookback = _lookback;
  }

  function setMaltRatioLookback(uint256 _lookback)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_lookback > 0, "Cannot have 0 lookback");
    maltRatioLookback = _lookback;
  }

  function setMaltPoolAverageContract(address _poolMA)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_poolMA != address(0), "Cannot use 0 address");
    poolMA = IDualMovingAverage(_poolMA);
  }

  function setMaltRatioAverageContract(address _ratioMA)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_ratioMA != address(0), "Cannot use 0 address");
    ratioMA = IMovingAverage(_ratioMA);
  }

  function setZ(uint256 _z)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_z != 0, "Cannot have 0 for Z");
    require(_z <= 100, "Cannot be over 100");
    z = _z;
  }

  function setSwingTraderLowBps(uint256 _swingTraderLowBps)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_swingTraderLowBps != 0, "Cannot have 0 Swing Trader Low BPS");
    require(
      _swingTraderLowBps <= 10000,
      "Cannot have a Swing Trader Low BPS greater than 10,000"
    );
    swingTraderLowBps = _swingTraderLowBps;
  }

  function setBreakpointBps(uint256 _breakpointBps)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_breakpointBps != 0, "Cannot have 0 breakpoint BPS");
    require(
      _breakpointBps <= 10000,
      "Cannot have a breakpoint BPS greater than 10,000"
    );
    breakpointBps = _breakpointBps;
  }

  function _accessControl()
    internal
    override(
      ImpliedCollateralServiceExtension,
      SwingTraderManagerExtension,
      GlobalICExtension
    )
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
