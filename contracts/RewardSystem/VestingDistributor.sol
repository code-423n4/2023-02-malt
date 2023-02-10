// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/RewardThrottleExtension.sol";
import "../interfaces/IBonding.sol";
import "../interfaces/IForfeit.sol";
import "../interfaces/IRewardMine.sol";

struct FocalPoint {
  uint256 id;
  uint256 focalLength;
  uint256 endTime;
  uint256 rewarded;
  uint256 vested;
  uint256 lastVestingTime;
}

/// @title Reward Vesting Distributor
/// @author 0xScotch <scotch@malt.money>
/// @notice The contract in charge of implementing the focal vesting scheme for rewards
contract VestingDistributor is StabilizedPoolUnit, RewardThrottleExtension {
  using SafeERC20 for ERC20;

  uint256 public focalID = 1; // Avoid issues with defaulting to 0
  uint256 public focalLength = 1 days;

  bytes32 public immutable REWARDER_ROLE;
  bytes32 public immutable REWARD_MINE_ROLE;
  bytes32 public immutable FOCAL_LENGTH_UPDATER_ROLE;

  IRewardMine public rewardMine;
  IForfeit public forfeitor;

  uint256 internal declaredBalance;
  uint256 internal vestedAccumulator;
  FocalPoint[] internal focalPoints;

  event DeclareReward(uint256 amount, address collateralToken);
  event Forfeit(address account, address collateralToken, uint256 forfeited);
  event RewardFocal(
    uint256 id,
    uint256 focalLength,
    uint256 endTime,
    uint256 rewarded
  );

  constructor(
    address timelock,
    address initialAdmin,
    address repository,
    address poolFactory
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    REWARDER_ROLE = 0xbeec13769b5f410b0584f69811bfd923818456d5edcf426b0e31cf90eed7a3f6;
    REWARD_MINE_ROLE = 0x9afd8e1abbfc72925a0e12f641b707c835ffa0861d61e98c38d65713ba5e2aff;
    FOCAL_LENGTH_UPDATER_ROLE = 0xfc161c35c622d802db78fe6212c2776c085a08e7a072c2d974d3764312eb42ab;

    _roleSetup(
      0xfc161c35c622d802db78fe6212c2776c085a08e7a072c2d974d3764312eb42ab,
      initialAdmin
    );

    focalPoints.push();
    focalPoints.push();
  }

  function setupContracts(
    address _collateralToken,
    address _rewardMine,
    address _rewardThrottle,
    address _forfeitor,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Only pool factory role") {
    require(!contractActive, "Distributor: Setup already done");
    require(_collateralToken != address(0), "Distributor: Col addr(0)");
    require(_rewardMine != address(0), "Distributor: RewardMine addr(0)");
    require(_rewardThrottle != address(0), "Distributor: Throttler addr(0)");
    require(_forfeitor != address(0), "Distributor: Forfeitor addr(0)");

    contractActive = true;

    _roleSetup(REWARDER_ROLE, _rewardThrottle);
    _roleSetup(REWARD_MINE_ROLE, _rewardMine);

    rewardMine = IRewardMine(_rewardMine);
    forfeitor = IForfeit(_forfeitor);

    collateralToken = ERC20(_collateralToken);
    rewardThrottle = IRewardThrottle(_rewardThrottle);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function vest() public {
    if (declaredBalance == 0) {
      return;
    }
    uint256 vestedReward = 0;
    uint256 balance = collateralToken.balanceOf(address(this));

    FocalPoint storage vestingFocal = _getVestingFocal();
    FocalPoint storage activeFocal = _updateAndGetActiveFocal();

    vestedReward = _getVestableQuantity(vestingFocal);
    uint256 activeReward = _getVestableQuantity(activeFocal);

    vestedReward = vestedReward + activeReward;

    if (vestedReward > balance) {
      vestedReward = balance;
    }

    if (vestedReward > 0) {
      if (rewardMine.totalBonded() == 0) {
        // There is no accounts to distribute the rewards to so forfeit it
        _forfeit(vestedReward);
        return;
      }
      // Send vested amount to liquidity mine
      vestedAccumulator += vestedReward;
      collateralToken.safeTransfer(address(rewardMine), vestedReward);
      rewardMine.releaseReward(vestedReward);
    }

    // increment focalID if time is past the halfway mark
    // through a focal period
    if (block.timestamp >= _getNextFocalStart(activeFocal)) {
      _incrementFocalPoint();
    }
  }

  /* PUBLIC VIEW FUNCTIONS */
  function totalDeclaredReward() public view returns (uint256) {
    return declaredBalance;
  }

  function getCurrentlyVested() public view returns (uint256) {
    return vestedAccumulator;
  }

  function bondedValue() public view returns (uint256) {
    return rewardMine.valueOfBonded();
  }

  function getAllFocalUnvestedBps()
    public
    view
    returns (uint256 currentUnvestedBps, uint256 vestingUnvestedBps)
  {
    uint256 currentId = focalID;

    FocalPoint storage currentFocal = focalPoints[_getFocalIndex(currentId)];
    FocalPoint storage vestingFocal = focalPoints[
      _getFocalIndex(currentId + 1)
    ];

    return (
      _getFocalUnvestedBps(currentFocal),
      _getFocalUnvestedBps(vestingFocal)
    );
  }

  function getFocalUnvestedBps(uint256 id)
    public
    view
    returns (uint256 unvestedBps)
  {
    FocalPoint storage currentFocal = focalPoints[_getFocalIndex(id)];

    return _getFocalUnvestedBps(currentFocal);
  }

  /* INTERNAL VIEW FUNCTIONS */
  function _getFocalUnvestedBps(FocalPoint memory focal)
    internal
    view
    returns (uint256)
  {
    uint256 periodLength = focal.focalLength;
    uint256 vestingEndTime = focal.endTime;

    if (block.timestamp >= vestingEndTime) {
      return 0;
    }

    return ((vestingEndTime - block.timestamp) * 10000) / periodLength;
  }

  function _getFocalIndex(uint256 id) internal pure returns (uint8 index) {
    return uint8(id % 2);
  }

  function _getVestingFocal() internal view returns (FocalPoint storage) {
    // Can add 1 as the modulo ensures we wrap correctly
    uint8 index = _getFocalIndex(focalID + 1);
    return focalPoints[index];
  }

  /* INTERNAL FUNCTIONS */
  function _updateAndGetActiveFocal() internal returns (FocalPoint storage) {
    uint8 index = _getFocalIndex(focalID);
    FocalPoint storage focal = focalPoints[index];

    if (focal.id != focalID) {
      // If id is not focalID then reinitialize the struct
      _resetFocalPoint(focalID, block.timestamp + focalLength);
    }

    return focal;
  }

  function _rewardCheck(uint256 reward) internal {
    require(reward > 0, "Cannot declare 0 reward");

    declaredBalance = declaredBalance + reward;

    uint256 totalReward = collateralToken.balanceOf(address(this)) +
      rewardMine.totalReleasedReward();

    require(declaredBalance <= totalReward, "Insufficient balance");
  }

  function _forfeit(uint256 forfeited) internal {
    require(forfeited <= declaredBalance, "Cannot forfeit more than declared");

    declaredBalance = declaredBalance - forfeited;

    _decrementFocalRewards(forfeited);

    collateralToken.safeTransfer(address(forfeitor), forfeited);
    forfeitor.handleForfeit();

    uint256 totalReward = collateralToken.balanceOf(address(this)) +
      rewardMine.totalReleasedReward();

    require(declaredBalance <= totalReward, "Insufficient balance");

    emit Forfeit(msg.sender, address(collateralToken), forfeited);
  }

  function _decrementFocalRewards(uint256 amount) internal {
    FocalPoint storage vestingFocal = _getVestingFocal();
    uint256 remainingVest = vestingFocal.rewarded - vestingFocal.vested;

    if (remainingVest >= amount) {
      vestingFocal.rewarded -= amount;
    } else {
      vestingFocal.rewarded -= remainingVest;
      remainingVest = amount - remainingVest;

      FocalPoint storage activeFocal = _updateAndGetActiveFocal();

      if (activeFocal.rewarded >= remainingVest) {
        activeFocal.rewarded -= remainingVest;
      } else {
        activeFocal.rewarded = 0;
      }
    }
  }

  function _resetFocalPoint(uint256 id, uint256 endTime) internal {
    uint8 index = _getFocalIndex(id);
    FocalPoint storage newFocal = focalPoints[index];

    newFocal.id = id;
    newFocal.focalLength = focalLength;
    newFocal.endTime = endTime;
    newFocal.rewarded = 0;
    newFocal.vested = 0;
    newFocal.lastVestingTime = endTime - focalLength;
  }

  function _incrementFocalPoint() internal {
    FocalPoint storage oldFocal = _updateAndGetActiveFocal();

    // This will increment every 24 hours so overflow on uint256
    // isn't an issue.
    focalID = focalID + 1;

    // Emit event that documents the focalPoint that has just ended
    emit RewardFocal(
      oldFocal.id,
      oldFocal.focalLength,
      oldFocal.endTime,
      oldFocal.rewarded
    );

    uint256 newEndTime = oldFocal.endTime + focalLength / 2;

    _resetFocalPoint(focalID, newEndTime);
  }

  function _getNextFocalStart(FocalPoint storage focal)
    internal
    view
    returns (uint256)
  {
    return focal.endTime - (focal.focalLength / 2);
  }

  function _getVestableQuantity(FocalPoint storage focal)
    internal
    returns (uint256 vestedReward)
  {
    uint256 currentTime = block.timestamp;

    if (focal.lastVestingTime >= currentTime) {
      return 0;
    }

    if (currentTime > focal.endTime) {
      currentTime = focal.endTime;
    }

    // Time in between last vesting call and end of focal period
    uint256 timeRemaining = focal.endTime - focal.lastVestingTime;

    if (timeRemaining == 0) {
      return 0;
    }

    // Time since last vesting call
    uint256 vestedTime = currentTime - focal.lastVestingTime;

    uint256 remainingReward = focal.rewarded - focal.vested;

    vestedReward = (remainingReward * vestedTime) / timeRemaining;

    focal.vested = focal.vested + vestedReward;
    focal.lastVestingTime = currentTime;

    return vestedReward;
  }

  /*
   * PRIVILEDGED METHODS
   */
  function declareReward(uint256 amount)
    external
    onlyRoleMalt(REWARDER_ROLE, "Only rewarder role")
  {
    _rewardCheck(amount);

    if (rewardMine.totalBonded() == 0) {
      // There is no accounts to distribute the rewards to so forfeit it
      _forfeit(amount);
      return;
    }

    // Vest current reward before adding new reward to ensure
    // Everything is up to date before we add new reward
    vest();

    FocalPoint storage activeFocal = _updateAndGetActiveFocal();
    activeFocal.rewarded = activeFocal.rewarded + amount;

    rewardMine.declareReward(amount);

    emit DeclareReward(amount, address(collateralToken));
  }

  function forfeit(uint256 amount)
    external
    onlyRoleMalt(REWARD_MINE_ROLE, "Only reward mine")
  {
    if (amount > 0) {
      _forfeit(amount);
    }
  }

  function decrementRewards(uint256 amount)
    external
    onlyRoleMalt(REWARD_MINE_ROLE, "Only reward mine")
  {
    require(
      amount <= declaredBalance,
      "Can't decrement more than total reward balance"
    );

    if (amount > 0) {
      declaredBalance = declaredBalance - amount;
    }
  }

  function setFocalLength(uint256 _focalLength)
    external
    onlyRoleMalt(FOCAL_LENGTH_UPDATER_ROLE, "Only focal length updater")
  {
    // Cannot have focal length under 1 hour
    require(_focalLength >= 3600, "Focal length too small");
    focalLength = _focalLength;
  }

  function _beforeSetRewardThrottle(address _rewardThrottle) internal override {
    _transferRole(_rewardThrottle, address(rewardThrottle), REWARDER_ROLE);
  }

  function setRewardMine(address _rewardMine)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_rewardMine != address(0), "Cannot set 0 address as rewardMine");
    _transferRole(_rewardMine, address(rewardMine), REWARD_MINE_ROLE);
    rewardMine = IRewardMine(_rewardMine);
  }

  function setForfeitor(address _forfeitor)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater privs")
  {
    require(_forfeitor != address(0), "Cannot set 0 address as forfeitor");
    forfeitor = IForfeit(_forfeitor);
  }

  function addFocalLengthUpdater(address _updater)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(
      _updater != address(0),
      "Cannot set 0 address as focal length updater"
    );
    _roleSetup(FOCAL_LENGTH_UPDATER_ROLE, _updater);
  }

  function removeFocalLengthUpdater(address _updater)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    _revokeRole(FOCAL_LENGTH_UPDATER_ROLE, _updater);
  }

  function _accessControl() internal override(RewardThrottleExtension) {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
