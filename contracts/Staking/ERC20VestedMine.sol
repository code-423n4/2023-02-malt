// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "./AbstractRewardMine.sol";
import "../interfaces/IDistributor.sol";
import "../interfaces/IBonding.sol";
import "../StabilizedPoolExtensions/BondingExtension.sol";

struct SharesAndDebt {
  uint256 totalImpliedReward;
  uint256 totalDebt;
  uint256 perShareReward;
  uint256 perShareDebt;
}

/// @title ERC20 Vested Mine
/// @author 0xScotch <scotch@malt.money>
/// @notice An implementation of AbstractRewardMine to handle rewards being vested by the RewardDistributor
contract ERC20VestedMine is AbstractRewardMine, BondingExtension {
  IVestingDistributor public vestingDistributor;

  uint256 internal shareUnity;

  mapping(uint256 => SharesAndDebt) internal focalSharesAndDebt;
  mapping(uint256 => mapping(address => SharesAndDebt))
    internal accountFocalSharesAndDebt;

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    uint256 _poolId
  ) AbstractRewardMine(timelock, repository, poolFactory) {
    poolId = _poolId;
    _grantRole(REWARD_PROVIDER_ROLE, timelock);
  }

  function setupContracts(
    address _miningService,
    address _vestingDistributor,
    address _bonding,
    address _collateralToken,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role") {
    require(!contractActive, "VestedMine: Already setup");
    require(_miningService != address(0), "VestedMine: MiningSvc addr(0)");
    require(
      _vestingDistributor != address(0),
      "VestedMine: Distributor addr(0)"
    );
    require(_bonding != address(0), "VestedMine: Bonding addr(0)");
    require(_collateralToken != address(0), "VestedMine: RewardToken addr(0)");

    contractActive = true;

    vestingDistributor = IVestingDistributor(_vestingDistributor);
    bonding = IBonding(_bonding);
    shareUnity = 10**bonding.stakeTokenDecimals();

    _initialSetup(_collateralToken, _miningService, _vestingDistributor);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function onUnbond(address account, uint256 amount)
    external
    override
    onlyRoleMalt(MINING_SERVICE_ROLE, "Must having mining service privilege")
  {
    // Withdraw all current rewards
    // Done now before we change stake padding below
    uint256 rewardEarned = earned(account);
    _handleWithdrawForAccount(account, rewardEarned, account);

    uint256 bondedBalance = balanceOfBonded(account);

    if (bondedBalance == 0) {
      return;
    }

    _checkForForfeit(account, amount, bondedBalance);

    uint256 lessStakePadding = (balanceOfStakePadding(account) * amount) /
      bondedBalance;

    _reconcileWithdrawn(account, amount, bondedBalance);
    _removeFromStakePadding(account, lessStakePadding);
  }

  function totalBonded() public view override returns (uint256) {
    return bonding.totalBondedByPool(poolId);
  }

  function valueOfBonded() public view override returns (uint256) {
    return bonding.valueOfBonded(poolId);
  }

  function balanceOfBonded(address account)
    public
    view
    override
    returns (uint256)
  {
    return bonding.balanceOfBonded(poolId, account);
  }

  /*
   * totalReleasedReward and totalDeclaredReward will often be the same. However, in the case
   * of vesting rewards they are different. In that case totalDeclaredReward is total
   * reward, including unvested. totalReleasedReward is just the rewards that have completed
   * the vesting schedule.
   */
  function totalDeclaredReward() public view override returns (uint256) {
    return vestingDistributor.totalDeclaredReward();
  }

  function declareReward(uint256 amount)
    external
    virtual
    onlyRoleMalt(REWARD_PROVIDER_ROLE, "Only reward provider role")
  {
    uint256 bonded = totalBonded();

    if (amount == 0 || bonded == 0) {
      return;
    }

    uint256 focalId = vestingDistributor.focalID();

    uint256 localShareUnity = shareUnity; // gas saving

    SharesAndDebt storage globalActiveFocalShares = focalSharesAndDebt[focalId];

    /*
     * normReward is normalizing the reward as if the reward was declared
     * at the very start of the focal period.
     * Eg if $100 reward comes in 33% towards the end of the vesting period
     * then that will look the same as $150 of rewards vesting from the very
     * beginning of the vesting period. However, to ensure that only $100
     * rewards are actual given out we accrue $50 of 'vesting debt'.
     *
     * To calculate how much has vested you first calculate what %
     * of the vesting period has elapsed. Then take that % of the
     * normReward and then subtract of normDebt.
     *
     * Using the above $100 at 33% into the vesting period as an example.
     * If we are 50% through the vesting period then 50% of the $150
     * normReward has vested = $75. Now subtract the $50 debt and
     * we are left with $25 of rewards.
     * This is correct as the $100 came in at 33.33% and we are now
     * 50% in, so we have moved 16.66% towards the 66.66% of the
     * remaining time. 16.66 is 25% of 66.66 so 25% of the $100 should
     * have vested.
     *
     * By normalizing rewards to always start and end vesting at the start
     * and end of the focal periods the math becomes significantly easier.
     * We also normalize the full normReward and normDebt to be per share
     * currently bonded which makes other math easier down the line.
     */

    uint256 unvestedBps = vestingDistributor.getFocalUnvestedBps(focalId);

    if (unvestedBps == 0) {
      return;
    }

    uint256 normReward = (amount * 10000) / unvestedBps;
    uint256 normDebt = normReward - amount;

    uint256 normRewardPerShare = (normReward * localShareUnity) / bonded;
    uint256 normDebtPerShare = (normDebt * localShareUnity) / bonded;

    focalSharesAndDebt[focalId].totalImpliedReward += normReward;
    focalSharesAndDebt[focalId].totalDebt += normDebt;
    focalSharesAndDebt[focalId].perShareReward += normRewardPerShare;
    focalSharesAndDebt[focalId].perShareDebt += normDebtPerShare;
  }

  function earned(address account)
    public
    view
    override
    returns (uint256 earnedReward)
  {
    uint256 totalAccountReward = balanceOfRewards(account);
    uint256 unvested = _getAccountUnvested(account);

    uint256 vested;

    if (totalAccountReward > unvested) {
      vested = totalAccountReward - unvested;
    }

    if (vested > _userWithdrawn[account]) {
      earnedReward = vested - _userWithdrawn[account];
    }

    uint256 balance = collateralToken.balanceOf(address(this));

    if (earnedReward > balance) {
      earnedReward = balance;
    }
  }

  function accountUnvested(address account) public view returns (uint256) {
    return _getAccountUnvested(account);
  }

  function getFocalShares(uint256 focalId)
    external
    view
    returns (
      uint256 totalImpliedReward,
      uint256 totalDebt,
      uint256 perShareReward,
      uint256 perShareDebt
    )
  {
    SharesAndDebt storage focalShares = focalSharesAndDebt[focalId];

    return (
      focalShares.totalImpliedReward,
      focalShares.totalDebt,
      focalShares.perShareReward,
      focalShares.perShareDebt
    );
  }

  function getAccountFocalDebt(address account, uint256 focalId)
    external
    view
    returns (uint256, uint256)
  {
    SharesAndDebt storage accountFocalDebt = accountFocalSharesAndDebt[focalId][
      account
    ];

    return (accountFocalDebt.perShareReward, accountFocalDebt.perShareDebt);
  }

  /*
   * INTERNAL FUNCTIONS
   */
  function _getAccountUnvested(address account)
    internal
    view
    returns (uint256 unvested)
  {
    // focalID starts at 1 so vesting can't underflow
    uint256 activeFocalId = vestingDistributor.focalID();
    uint256 vestingFocalId = activeFocalId - 1;
    uint256 userBonded = balanceOfBonded(account);

    uint256 activeUnvestedPerShare = _getFocalUnvestedPerShare(
      activeFocalId,
      account
    );
    uint256 vestingUnvestedPerShare = _getFocalUnvestedPerShare(
      vestingFocalId,
      account
    );

    unvested =
      ((activeUnvestedPerShare + vestingUnvestedPerShare) * userBonded) /
      shareUnity;
  }

  function _getFocalUnvestedPerShare(uint256 focalId, address account)
    internal
    view
    returns (uint256 unvestedPerShare)
  {
    SharesAndDebt storage globalActiveFocalShares = focalSharesAndDebt[focalId];
    SharesAndDebt storage accountActiveFocalShares = accountFocalSharesAndDebt[
      focalId
    ][account];
    uint256 bonded = totalBonded();

    if (globalActiveFocalShares.perShareReward == 0 || bonded == 0) {
      return 0;
    }

    uint256 unvestedBps = vestingDistributor.getFocalUnvestedBps(focalId);
    uint256 vestedBps = 10000 - unvestedBps;

    uint256 totalRewardPerShare = globalActiveFocalShares.perShareReward -
      globalActiveFocalShares.perShareDebt;
    uint256 totalUserDebtPerShare = accountActiveFocalShares.perShareReward -
      accountActiveFocalShares.perShareDebt;

    uint256 rewardPerShare = ((globalActiveFocalShares.perShareReward *
      vestedBps) / 10000) - globalActiveFocalShares.perShareDebt;
    uint256 userDebtPerShare = ((accountActiveFocalShares.perShareReward *
      vestedBps) / 10000) - accountActiveFocalShares.perShareDebt;

    uint256 userTotalPerShare = totalRewardPerShare - totalUserDebtPerShare;
    uint256 userVestedPerShare = rewardPerShare - userDebtPerShare;

    if (userTotalPerShare > userVestedPerShare) {
      unvestedPerShare = userTotalPerShare - userVestedPerShare;
    }
  }

  function _afterBond(address account, uint256 amount) internal override {
    uint256 focalId = vestingDistributor.focalID();
    uint256 vestingFocalId = focalId - 1;

    uint256 initialUserBonded = balanceOfBonded(account);
    uint256 userTotalBonded = initialUserBonded + amount;

    SharesAndDebt memory currentShares = focalSharesAndDebt[focalId];
    SharesAndDebt memory vestingShares = focalSharesAndDebt[vestingFocalId];

    uint256 perShare = accountFocalSharesAndDebt[focalId][account]
      .perShareReward;
    uint256 vestingPerShare = accountFocalSharesAndDebt[vestingFocalId][account]
      .perShareReward;

    if (
      currentShares.perShareReward == 0 && vestingShares.perShareReward == 0
    ) {
      return;
    }

    uint256 debt = accountFocalSharesAndDebt[focalId][account].perShareDebt;
    uint256 vestingDebt = accountFocalSharesAndDebt[vestingFocalId][account]
      .perShareDebt;

    // Pro-rata it down according to old bonded value
    perShare = (perShare * initialUserBonded) / userTotalBonded;
    debt = (debt * initialUserBonded) / userTotalBonded;

    vestingPerShare = (vestingPerShare * initialUserBonded) / userTotalBonded;
    vestingDebt = (vestingDebt * initialUserBonded) / userTotalBonded;

    // Now add on the new pro-ratad perShare values
    perShare += (currentShares.perShareReward * amount) / userTotalBonded;
    debt += (currentShares.perShareDebt * amount) / userTotalBonded;

    vestingPerShare +=
      (vestingShares.perShareReward * amount) /
      userTotalBonded;
    vestingDebt += (vestingShares.perShareDebt * amount) / userTotalBonded;

    accountFocalSharesAndDebt[focalId][account].perShareReward = perShare;
    accountFocalSharesAndDebt[focalId][account].perShareDebt = debt;

    accountFocalSharesAndDebt[vestingFocalId][account]
      .perShareReward = vestingPerShare;
    accountFocalSharesAndDebt[vestingFocalId][account]
      .perShareDebt = vestingDebt;
  }

  function _checkForForfeit(
    address account,
    uint256 amount,
    uint256 bondedBalance
  ) internal {
    // The user is unbonding so we should reduce declaredReward
    // proportional to the unbonded amount
    // At any given point in time, every user has rewards allocated
    // to them. balanceOfRewards(account) will tell you this value.
    // If a user unbonds x% of their LP then declaredReward should
    // reduce by exactly x% of that user's allocated rewards

    // However, this has to be done in 2 parts. First forfeit x%
    // Of unvested rewards. This decrements declaredReward automatically.
    // Then we call decrementRewards using x% of rewards that have
    // already been released. The net effect is declaredReward decreases
    // by x% of the users allocated reward

    uint256 unvested = _getAccountUnvested(account);

    uint256 forfeitReward = (unvested * amount) / bondedBalance;

    // A full withdrawn happens before this method is called.
    // So we can safely say _userWithdrawn is in fact all of the
    // currently vested rewards for the bonded LP
    uint256 declaredRewardDecrease = (_userWithdrawn[account] * amount) /
      bondedBalance;

    if (forfeitReward > 0) {
      vestingDistributor.forfeit(forfeitReward);
    }

    if (declaredRewardDecrease > 0) {
      vestingDistributor.decrementRewards(declaredRewardDecrease);
    }
  }

  function _beforeWithdraw(address account, uint256 amount) internal override {
    // Vest rewards before withdrawing to make sure all capital is available
    vestingDistributor.vest();
  }

  /*
   * PRIVILEDGED FUNCTIONS
   */
  function setVestingDistributor(address _vestingDistributor)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    vestingDistributor = IVestingDistributor(_vestingDistributor);
  }

  function _accessControl()
    internal
    override(MiningServiceExtension, BondingExtension)
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
