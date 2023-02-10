// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/RewardThrottleExtension.sol";
import "../interfaces/IForfeit.sol";
import "../interfaces/IRewardMine.sol";
import "../interfaces/IDistributor.sol";

/// @title Linear Distributor
/// @author 0xScotch <scotch@malt.money>
/// @notice The contract in charge of implementing the linear distribution of rewards in line with the vesting APR
contract LinearDistributor is
  StabilizedPoolUnit,
  IDistributor,
  RewardThrottleExtension
{
  using SafeERC20 for ERC20;

  bytes32 public immutable REWARDER_ROLE;
  bytes32 public immutable REWARD_MINE_ROLE;

  IRewardMine public rewardMine;
  IForfeit public forfeitor;
  IVestingDistributor public vestingDistributor;

  uint256 public bufferTime = 1 days;

  uint256 internal previouslyVested;
  uint256 internal previouslyVestedTimestamp;

  uint256 internal declaredBalance;

  event DeclareReward(
    uint256 totalAmount,
    uint256 usedAmount,
    address collateralToken
  );
  event Forfeit(uint256 forfeited);

  constructor(
    address timelock,
    address repository,
    address poolFactory
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    REWARDER_ROLE = 0xbeec13769b5f410b0584f69811bfd923818456d5edcf426b0e31cf90eed7a3f6;
    REWARD_MINE_ROLE = 0x9afd8e1abbfc72925a0e12f641b707c835ffa0861d61e98c38d65713ba5e2aff;
  }

  function setupContracts(
    address _collateralToken,
    address _rewardMine,
    address _rewardThrottle,
    address _forfeitor,
    address _vestingDistributor,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Only pool factory role") {
    require(!contractActive, "Distributor: Setup already done");
    require(_collateralToken != address(0), "Distributor: Col addr(0)");
    require(_rewardMine != address(0), "Distributor: RewardMine addr(0)");
    require(_rewardThrottle != address(0), "Distributor: Throttler addr(0)");
    require(_forfeitor != address(0), "Distributor: Forfeitor addr(0)");
    require(
      _vestingDistributor != address(0),
      "Distributor: VestingDist addr(0)"
    );

    contractActive = true;

    _roleSetup(REWARDER_ROLE, _rewardThrottle);
    _roleSetup(REWARD_MINE_ROLE, _rewardMine);

    collateralToken = ERC20(_collateralToken);
    rewardMine = IRewardMine(_rewardMine);
    rewardThrottle = IRewardThrottle(_rewardThrottle);
    forfeitor = IForfeit(_forfeitor);
    vestingDistributor = IVestingDistributor(_vestingDistributor);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  /* PUBLIC VIEW FUNCTIONS */
  function totalDeclaredReward() public view returns (uint256) {
    return declaredBalance;
  }

  function bondedValue() public view returns (uint256) {
    return rewardMine.valueOfBonded();
  }

  /*
   * PRIVILEDGED METHODS
   */
  function declareReward(uint256 amount)
    external
    onlyRoleMalt(REWARDER_ROLE, "Only rewarder role")
    onlyActive
  {
    _rewardCheck(amount);

    if (rewardMine.totalBonded() == 0) {
      // There is no accounts to distribute the rewards to so forfeit it
      _forfeit(amount);
      return;
    }

    uint256 vestingBondedValue = vestingDistributor.bondedValue();
    uint256 currentlyVested = vestingDistributor.getCurrentlyVested();

    uint256 netVest = currentlyVested - previouslyVested;
    uint256 netTime = block.timestamp - previouslyVestedTimestamp;

    if (netVest == 0 || vestingBondedValue == 0) {
      return;
    }

    uint256 linearBondedValue = rewardMine.valueOfBonded();

    uint256 distributed = (linearBondedValue * netVest) / vestingBondedValue;
    uint256 balance = collateralToken.balanceOf(address(this));

    if (distributed > balance) {
      distributed = balance;
    }

    if (distributed > 0) {
      // Send vested amount to liquidity mine
      collateralToken.safeTransfer(address(rewardMine), distributed);
      rewardMine.releaseReward(distributed);
    }

    balance = collateralToken.balanceOf(address(this));

    uint256 buf = bufferTime; // gas
    uint256 bufferRequirement;

    if (netTime < buf) {
      bufferRequirement = (distributed * buf * 10000) / netTime / 10000;
    } else {
      bufferRequirement = distributed;
    }

    if (balance > bufferRequirement) {
      // We have more than the buffer required. Forfeit the rest
      uint256 net = balance - bufferRequirement;
      _forfeit(net);
    }

    previouslyVested = currentlyVested;
    previouslyVestedTimestamp = block.timestamp;

    emit DeclareReward(amount, distributed, address(collateralToken));
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

  /* INTERNAL FUNCTIONS */
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

    collateralToken.safeTransfer(address(forfeitor), forfeited);
    forfeitor.handleForfeit();

    uint256 totalReward = collateralToken.balanceOf(address(this)) +
      rewardMine.totalReleasedReward();

    require(declaredBalance <= totalReward, "Insufficient balance");

    emit Forfeit(forfeited);
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

  function setVestingDistributor(address _vestingDistributor)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_vestingDistributor != address(0), "SetVestDist: No addr(0)");
    vestingDistributor = IVestingDistributor(_vestingDistributor);
  }

  function setBufferTime(uint256 _bufferTime)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    bufferTime = _bufferTime;
  }

  function _accessControl() internal override(RewardThrottleExtension) {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
