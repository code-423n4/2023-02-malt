// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/utils/math/Math.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/BondingExtension.sol";
import "../StabilizedPoolExtensions/RewardOverflowExtension.sol";
import "../interfaces/ITimekeeper.sol";
import "../interfaces/IOverflow.sol";
import "../interfaces/IBonding.sol";
import "../interfaces/IDistributor.sol";

struct State {
  uint256 profit;
  uint256 rewarded;
  uint256 bondedValue;
  uint256 epochsPerYear;
  uint256 desiredAPR;
  uint256 cumulativeCashflowApr;
  uint256 cumulativeApr;
  bool active;
}

/// @title Reward Throttle
/// @author 0xScotch <scotch@malt.money>
/// @notice The contract in charge of smoothing out rewards and attempting to find a steady APR
contract RewardThrottle is
  StabilizedPoolUnit,
  BondingExtension,
  RewardOverflowExtension
{
  using SafeERC20 for ERC20;

  ITimekeeper public timekeeper;

  // Admin updatable params
  uint256 public smoothingPeriod = 24; // 24 epochs = 12 hours
  uint256 public desiredRunway = 15778800; // 6 months
  // uint256 public desiredRunway = 2629800; // 1 months
  uint256 public aprCap = 5000; // 50%
  uint256 public aprFloor = 200; // 2%
  uint256 public aprUpdatePeriod = 2 hours;
  uint256 public cushionBps = 10000; // 100%
  uint256 public maxAdjustment = 50; // 0.5%
  uint256 public proportionalGainBps = 1000; // 10% ie proportional gain factor of 0.1

  // Not externall updatable
  uint256 public targetAPR = 1000; // 10%
  uint256 public aprLastUpdated;

  uint256 public activeEpoch;
  mapping(uint256 => State) public state;

  event RewardOverflow(uint256 epoch, uint256 overflow);
  event HandleReward(uint256 epoch, uint256 amount);
  event UpdateDesiredAPR(uint256 apr);

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    address _timekeeper
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    require(_timekeeper != address(0), "Throttle: Timekeeper addr(0)");

    timekeeper = ITimekeeper(_timekeeper);
    aprLastUpdated = block.timestamp;
  }

  function setupContracts(
    address _collateralToken,
    address _overflowPool,
    address _bonding,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Only pool factory role") {
    require(!contractActive, "RewardThrottle: Already setup");
    require(_collateralToken != address(0), "RewardThrottle: Col addr(0)");
    require(_overflowPool != address(0), "RewardThrottle: Overflow addr(0)");
    require(_bonding != address(0), "RewardThrottle: Bonding addr(0)");

    contractActive = true;

    collateralToken = ERC20(_collateralToken);
    overflowPool = IOverflow(_overflowPool);
    bonding = IBonding(_bonding);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function handleReward() external onlyActive {
    updateDesiredAPR();

    uint256 balance = collateralToken.balanceOf(address(this));

    uint256 epoch = timekeeper.epoch();

    uint256 _activeEpoch = activeEpoch; // gas

    state[_activeEpoch].profit += balance;

    // Fetch targetAPR before we update current epoch state
    uint256 aprTarget = targetAPR; // gas

    // Distribute balance to the correct places
    if (aprTarget > 0 && _epochAprGivenReward(epoch, balance) > aprTarget) {
      uint256 remainder = _getRewardOverflow(balance, aprTarget, _activeEpoch);
      emit RewardOverflow(_activeEpoch, remainder);

      if (remainder > 0) {
        collateralToken.safeTransfer(address(overflowPool), remainder);

        if (balance > remainder) {
          balance -= remainder;
        } else {
          balance = 0;
        }
      }
    }

    if (balance > 0) {
      _sendToDistributor(balance, _activeEpoch);
    }

    emit HandleReward(epoch, balance);
  }

  function updateDesiredAPR() public onlyActive {
    checkRewardUnderflow();

    if (aprLastUpdated + aprUpdatePeriod > block.timestamp) {
      // Too early to update
      return;
    }

    uint256 cashflowAverageApr = averageCashflowAPR(smoothingPeriod);

    uint256 newAPR = targetAPR; // gas
    uint256 adjustmentCap = maxAdjustment; // gas
    uint256 targetCashflowApr = (newAPR * (10000 + cushionBps)) / 10000;

    if (cashflowAverageApr > targetCashflowApr) {
      uint256 delta = cashflowAverageApr - targetCashflowApr;
      uint256 adjustment = (delta * proportionalGainBps) / 10000;

      if (adjustment > adjustmentCap) {
        adjustment = adjustmentCap;
      }

      newAPR += adjustment;
    } else if (cashflowAverageApr < targetCashflowApr) {
      uint256 deficit = runwayDeficit();

      if (deficit == 0) {
        aprLastUpdated = block.timestamp;
        return;
      }

      uint256 delta = targetCashflowApr - cashflowAverageApr;
      uint256 adjustment = (delta * proportionalGainBps) / 10000;

      if (adjustment > adjustmentCap) {
        adjustment = adjustmentCap;
      }

      newAPR -= adjustment;
    }

    uint256 cap = aprCap; // gas
    uint256 floor = aprFloor; // gas
    if (newAPR > cap) {
      newAPR = cap;
    } else if (newAPR < floor) {
      newAPR = floor;
    }

    targetAPR = newAPR;
    aprLastUpdated = block.timestamp;
    emit UpdateDesiredAPR(newAPR);
  }

  /*
   * PUBLIC VIEW FUNCTIONS
   */
  function epochAPR(uint256 epoch) public view returns (uint256) {
    // This returns an implied APR based on the distributed rewards and bonded LP at the given epoch
    State memory epochState = state[epoch];

    uint256 bondedValue = epochState.bondedValue;
    if (bondedValue == 0) {
      bondedValue = bonding.averageBondedValue(epoch);
      if (bondedValue == 0) {
        return 0;
      }
    }

    uint256 epochsPerYear = epochState.epochsPerYear;

    if (epochsPerYear == 0) {
      epochsPerYear = timekeeper.epochsPerYear();
    }

    // 10000 = 100%
    return (epochState.rewarded * 10000 * epochsPerYear) / bondedValue;
  }

  function averageCashflowAPR(uint256 averagePeriod)
    public
    view
    returns (uint256 apr)
  {
    uint256 currentEpoch = activeEpoch; // gas
    uint256 endEpoch = currentEpoch; // previous epoch
    uint256 startEpoch;

    if (endEpoch < averagePeriod) {
      averagePeriod = currentEpoch;
    } else {
      startEpoch = endEpoch - averagePeriod;
    }

    if (startEpoch == endEpoch || averagePeriod == 0) {
      return epochCashflowAPR(endEpoch);
    }

    State memory startEpochState = state[startEpoch];
    State memory endEpochState = state[endEpoch];

    if (
      startEpochState.cumulativeCashflowApr >=
      endEpochState.cumulativeCashflowApr
    ) {
      return 0;
    }

    uint256 delta = endEpochState.cumulativeCashflowApr -
      startEpochState.cumulativeCashflowApr;

    apr = delta / averagePeriod;
  }

  function averageCashflowAPR(uint256 startEpoch, uint256 endEpoch)
    public
    view
    returns (uint256 apr)
  {
    require(startEpoch <= endEpoch, "Start cannot be before the end");

    if (startEpoch == endEpoch) {
      return epochCashflowAPR(endEpoch);
    }

    uint256 averagePeriod = endEpoch - startEpoch;

    State memory startEpochState = state[startEpoch];
    State memory endEpochState = state[endEpoch];

    if (
      startEpochState.cumulativeCashflowApr >=
      endEpochState.cumulativeCashflowApr
    ) {
      return 0;
    }

    uint256 delta = endEpochState.cumulativeCashflowApr -
      startEpochState.cumulativeCashflowApr;

    apr = delta / averagePeriod;
  }

  function epochCashflow(uint256 epoch) public view returns (uint256 cashflow) {
    State memory epochState = state[epoch];

    cashflow = epochState.profit;

    if (epochState.rewarded > cashflow) {
      cashflow = epochState.rewarded;
    }
  }

  function epochCashflowAPR(uint256 epoch)
    public
    view
    returns (uint256 cashflowAPR)
  {
    State memory epochState = state[epoch];

    uint256 cashflow = epochState.profit;

    if (epochState.rewarded > cashflow) {
      cashflow = epochState.rewarded;
    }

    uint256 bondedValue = epochState.bondedValue;
    if (bondedValue == 0) {
      bondedValue = bonding.averageBondedValue(epoch);
      if (bondedValue == 0) {
        return 0;
      }
    }

    uint256 epochsPerYear = epochState.epochsPerYear;

    if (epochsPerYear == 0) {
      epochsPerYear = timekeeper.epochsPerYear();
    }

    // 10000 = 100%
    return (cashflow * 10000 * epochsPerYear) / bondedValue;
  }

  function averageAPR(uint256 startEpoch, uint256 endEpoch)
    public
    view
    returns (uint256 apr)
  {
    require(startEpoch <= endEpoch, "Start cannot be before the end");

    if (startEpoch == endEpoch) {
      return epochAPR(startEpoch);
    }

    uint256 averagePeriod = endEpoch - startEpoch;

    State memory startEpochState = state[startEpoch];
    State memory endEpochState = state[endEpoch];

    if (startEpochState.cumulativeApr >= endEpochState.cumulativeApr) {
      return 0;
    }

    uint256 delta = endEpochState.cumulativeApr - startEpochState.cumulativeApr;

    apr = delta / averagePeriod;
  }

  function targetEpochProfit() public view returns (uint256) {
    uint256 epoch = timekeeper.epoch();
    (, uint256 epochProfitTarget) = getTargets(epoch);
    return epochProfitTarget;
  }

  function getTargets(uint256 epoch)
    public
    view
    returns (uint256 aprTarget, uint256 profitTarget)
  {
    State memory epochState = state[epoch];

    aprTarget = epochState.desiredAPR;

    if (aprTarget == 0) {
      aprTarget = targetAPR;
    }

    uint256 bondedValue = epochState.bondedValue;
    if (bondedValue == 0) {
      bondedValue = bonding.averageBondedValue(epoch);
    }

    uint256 epochsPerYear = epochState.epochsPerYear;
    if (epochsPerYear == 0) {
      epochsPerYear = timekeeper.epochsPerYear();
    }

    profitTarget = (aprTarget * bondedValue) / epochsPerYear / 10000;

    return (aprTarget, profitTarget);
  }

  function runwayDeficit() public view returns (uint256) {
    uint256 overflowBalance = collateralToken.balanceOf(address(overflowPool));

    uint256 epochTargetProfit = targetEpochProfit();
    // 31557600 is seconds in a year
    uint256 runwayEpochs = (timekeeper.epochsPerYear() * desiredRunway) /
      31557600;
    uint256 requiredProfit = epochTargetProfit * runwayEpochs;

    if (overflowBalance < requiredProfit) {
      return requiredProfit - overflowBalance;
    }

    return 0;
  }

  /// @notice Returns the number of epochs of APR we have in runway
  function runway()
    external
    view
    returns (uint256 runwayEpochs, uint256 runwayDays)
  {
    uint256 overflowBalance = collateralToken.balanceOf(address(overflowPool));
    uint256 epochTargetProfit = targetEpochProfit();
    // 86400 seconds in a day
    uint256 epochsPerDay = 86400 / timekeeper.epochLength();

    if (epochTargetProfit == 0 || epochsPerDay == 0) {
      return (0, 0);
    }

    runwayEpochs = overflowBalance / epochTargetProfit;
    runwayDays = runwayEpochs / epochsPerDay;
  }

  function epochState(uint256 epoch) public view returns (State memory) {
    return state[epoch];
  }

  function epochData(uint256 epoch)
    public
    view
    returns (
      uint256 profit,
      uint256 rewarded,
      uint256 bondedValue,
      uint256 desiredAPR,
      uint256 epochsPerYear,
      uint256 cumulativeCashflowApr,
      uint256 cumulativeApr
    )
  {
    return (
      state[epoch].profit,
      state[epoch].rewarded,
      state[epoch].bondedValue,
      state[epoch].desiredAPR,
      state[epoch].epochsPerYear,
      state[epoch].cumulativeCashflowApr,
      state[epoch].cumulativeApr
    );
  }

  function checkRewardUnderflow() public onlyActive {
    uint256 epoch = timekeeper.epoch();

    uint256 _activeEpoch = activeEpoch; // gas

    // Fill in gaps so we have a fresh foundation to calculate from
    _fillInEpochGaps(epoch);

    if (epoch > _activeEpoch) {
      for (uint256 i = _activeEpoch; i < epoch; ++i) {
        uint256 underflow = _getRewardUnderflow(i);

        if (underflow > 0) {
          uint256 balance = overflowPool.requestCapital(underflow);

          _sendToDistributor(balance, i);
        }
      }
    }
  }

  function fillInEpochGaps() external {
    uint256 epoch = timekeeper.epoch();

    _fillInEpochGaps(epoch);
  }

  function fillInEpochGaps(uint256 epoch) external {
    uint256 actualEpoch = timekeeper.epoch();
    require(epoch <= actualEpoch && epoch > activeEpoch, "Invalid epoch");

    _fillInEpochGaps(epoch);
  }

  /*
   * INTERNAL VIEW FUNCTIONS
   */
  function _epochAprGivenReward(uint256 epoch, uint256 reward)
    internal
    view
    returns (uint256)
  {
    // This returns an implied APR based on the distributed rewards and bonded LP at the given epoch
    State memory epochState = state[epoch];
    uint256 bondedValue = epochState.bondedValue;

    if (bondedValue == 0) {
      bondedValue = bonding.averageBondedValue(epoch);
      if (bondedValue == 0) {
        return 0;
      }
    }

    uint256 epochsPerYear = epochState.epochsPerYear;

    if (epochsPerYear == 0) {
      epochsPerYear = timekeeper.epochsPerYear();
    }

    // 10000 = 100%
    return
      ((epochState.rewarded + reward) * 10000 * epochsPerYear) / bondedValue;
  }

  function _getRewardOverflow(
    uint256 declaredReward,
    uint256 desiredAPR,
    uint256 epoch
  ) internal view returns (uint256 remainder) {
    State memory epochState = state[epoch];

    if (desiredAPR == 0) {
      // If desired APR is zero then just allow all rewards through
      return 0;
    }

    uint256 epochsPerYear = epochState.epochsPerYear;

    if (epochsPerYear == 0) {
      epochsPerYear = timekeeper.epochsPerYear();
    }

    uint256 bondedValue = epochState.bondedValue;

    if (bondedValue == 0) {
      bondedValue = bonding.averageBondedValue(epoch);
    }

    uint256 targetProfit = (desiredAPR * bondedValue) / epochsPerYear / 10000;

    if (targetProfit <= epochState.rewarded) {
      return declaredReward;
    }

    uint256 undeclaredReward = targetProfit - epochState.rewarded;

    if (undeclaredReward >= declaredReward) {
      // Declared reward doesn't make up for the difference yet
      return 0;
    }

    remainder = declaredReward - undeclaredReward;
  }

  function _getRewardUnderflow(uint256 epoch)
    internal
    view
    returns (uint256 amount)
  {
    State memory epochState = state[epoch];

    uint256 epochsPerYear = epochState.epochsPerYear;

    if (epochsPerYear == 0) {
      epochsPerYear = timekeeper.epochsPerYear();
    }

    uint256 bondedValue = epochState.bondedValue;

    if (bondedValue == 0) {
      bondedValue = bonding.averageBondedValue(epoch);
    }

    uint256 targetProfit = (epochState.desiredAPR * bondedValue) /
      epochsPerYear /
      10000;

    if (targetProfit <= epochState.rewarded) {
      // Rewarded more than target already. 0 underflow
      return 0;
    }

    return targetProfit - epochState.rewarded;
  }

  /*
   * INTERNAL FUNCTIONS
   */
  function _sendToDistributor(uint256 amount, uint256 epoch) internal {
    if (amount == 0) {
      return;
    }

    (
      uint256[] memory poolIds,
      uint256[] memory allocations,
      address[] memory distributors
    ) = bonding.poolAllocations();

    uint256 length = poolIds.length;
    uint256 balance = collateralToken.balanceOf(address(this));
    uint256 rewarded;

    for (uint256 i; i < length; ++i) {
      uint256 share = (amount * allocations[i]) / 1e18;

      if (share == 0) {
        continue;
      }

      if (share > balance) {
        share = balance;
      }

      collateralToken.safeTransfer(distributors[i], share);
      IDistributor(distributors[i]).declareReward(share);
      balance -= share;
      rewarded += share;

      if (balance == 0) {
        break;
      }
    }

    state[epoch].rewarded = state[epoch].rewarded + rewarded;
    state[epoch + 1].cumulativeCashflowApr =
      state[epoch].cumulativeCashflowApr +
      epochCashflowAPR(epoch);
    state[epoch + 1].cumulativeApr =
      state[epoch].cumulativeApr +
      epochAPR(epoch);
    state[epoch].bondedValue = bonding.averageBondedValue(epoch);
  }

  function _fillInEpochGaps(uint256 epoch) internal {
    uint256 epochsPerYear = timekeeper.epochsPerYear();
    uint256 _activeEpoch = activeEpoch; // gas

    state[_activeEpoch].bondedValue = bonding.averageBondedValue(_activeEpoch);
    state[_activeEpoch].epochsPerYear = epochsPerYear;
    state[_activeEpoch].desiredAPR = targetAPR;

    if (_activeEpoch > 0) {
      state[_activeEpoch].cumulativeCashflowApr =
        state[_activeEpoch - 1].cumulativeCashflowApr +
        epochCashflowAPR(_activeEpoch - 1);
      state[_activeEpoch].cumulativeApr =
        state[_activeEpoch - 1].cumulativeApr +
        epochAPR(_activeEpoch - 1);
    }

    // Avoid issues if gap between rewards is greater than one epoch
    for (uint256 i = _activeEpoch + 1; i <= epoch; ++i) {
      if (!state[i].active) {
        state[i].bondedValue = bonding.averageBondedValue(i);
        state[i].profit = 0;
        state[i].rewarded = 0;
        state[i].epochsPerYear = epochsPerYear;
        state[i].desiredAPR = targetAPR;
        state[i].cumulativeCashflowApr =
          state[i - 1].cumulativeCashflowApr +
          epochCashflowAPR(i - 1);
        state[i].cumulativeApr = state[i - 1].cumulativeApr + epochAPR(i - 1);
        state[i].active = true;
      }
    }

    activeEpoch = epoch;
  }

  /*
   * PRIVILEDGED FUNCTIONS
   */
  function populateFromPreviousThrottle(address previousThrottle, uint256 epoch)
    external
    onlyRoleMalt(ADMIN_ROLE, "Only admin role")
  {
    RewardThrottle previous = RewardThrottle(previousThrottle);
    uint256 _activeEpoch = activeEpoch; // gas

    for (uint256 i = _activeEpoch; i < epoch; ++i) {
      (
        uint256 profit,
        uint256 rewarded,
        uint256 bondedValue,
        uint256 desiredAPR,
        uint256 epochsPerYear,
        uint256 cumulativeCashflowApr,
        uint256 cumulativeApr
      ) = previous.epochData(i);

      state[i].bondedValue = bondedValue;
      state[i].profit = profit;
      state[i].rewarded = rewarded;
      state[i].epochsPerYear = epochsPerYear;
      state[i].desiredAPR = desiredAPR;
      state[i].cumulativeCashflowApr = cumulativeCashflowApr;
      state[i].cumulativeApr = cumulativeApr;
    }

    activeEpoch = epoch;
  }

  function setTimekeeper(address _timekeeper)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater privs")
  {
    require(_timekeeper != address(0), "Not address 0");
    timekeeper = ITimekeeper(_timekeeper);
  }

  function setSmoothingPeriod(uint256 _smoothingPeriod)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_smoothingPeriod > 0, "No zero smoothing period");
    smoothingPeriod = _smoothingPeriod;
  }

  function setDesiredRunway(uint256 _runway)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_runway > 604800, "Runway must be > 1 week");
    desiredRunway = _runway;
  }

  function setAprCap(uint256 _aprCap)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_aprCap != 0, "Cap cannot be 0");
    aprCap = _aprCap;
  }

  function setAprFloor(uint256 _aprFloor)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_aprFloor != 0, "Floor cannot be 0");
    aprFloor = _aprFloor;
  }

  function setUpdatePeriod(uint256 _period)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_period >= timekeeper.epochLength(), "< 1 epoch");
    aprUpdatePeriod = _period;
  }

  function setCushionBps(uint256 _cushionBps)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_cushionBps != 0, "Cannot be 0");
    cushionBps = _cushionBps;
  }

  function setMaxAdjustment(uint256 _max)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_max != 0, "Cannot be 0");
    maxAdjustment = _max;
  }

  function setProportionalGain(uint256 _gain)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_gain != 0 && _gain < 10000, "Between 1-9999 inc");
    proportionalGainBps = _gain;
  }

  function _accessControl()
    internal
    override(BondingExtension, RewardOverflowExtension)
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
