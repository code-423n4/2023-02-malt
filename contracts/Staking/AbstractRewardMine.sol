// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/MiningServiceExtension.sol";

/// @title Abstract Reward Mine
/// @author 0xScotch <scotch@malt.money>
/// @notice The base functionality for tracking user reward ownership, withdrawals etc
/// @dev The contract is abstract so needs to be inherited
abstract contract AbstractRewardMine is
  StabilizedPoolUnit,
  MiningServiceExtension
{
  using SafeERC20 for ERC20;

  bytes32 public immutable REWARD_MANAGER_ROLE;
  bytes32 public immutable MINING_SERVICE_ROLE;
  bytes32 public immutable REWARD_PROVIDER_ROLE;

  uint256 public poolId;

  uint256 internal _globalStakePadding;
  uint256 internal _globalWithdrawn;
  uint256 internal _globalReleased;
  mapping(address => uint256) internal _userStakePadding;
  mapping(address => uint256) internal _userWithdrawn;

  event Withdraw(address indexed account, uint256 rewarded, address indexed to);
  event SetPoolId(uint256 _poolId);

  constructor(
    address timelock,
    address initialAdmin,
    address poolFactory
  ) StabilizedPoolUnit(timelock, initialAdmin, poolFactory) {
    REWARD_MANAGER_ROLE = 0x0f51adb3f49e4a9bbb17b3783f025995eaf8c24be2c8eefff214bdfda05ef94d;
    MINING_SERVICE_ROLE = 0x946341637d150f85502674c6b415a62cb11e7566d5cfeb8b2f092551dc44a49c;
    REWARD_PROVIDER_ROLE = 0xf1f0183ef0e4c6c02c1d4fe58f4f2ffeae0c949e3f0bba2d690f5cb39aee89af;
  }

  function onBond(address account, uint256 amount)
    external
    virtual
    onlyRoleMalt(MINING_SERVICE_ROLE, "Must having mining service privilege")
  {
    _beforeBond(account, amount);
    _handleStakePadding(account, amount);
    _afterBond(account, amount);
  }

  function onUnbond(address account, uint256 amount)
    external
    virtual
    onlyRoleMalt(MINING_SERVICE_ROLE, "Must having mining service privilege")
  {
    _beforeUnbond(account, amount);
    // Withdraw all current rewards
    // Done now before we change stake padding below
    uint256 rewardEarned = earned(account);
    _handleWithdrawForAccount(account, rewardEarned, account);

    uint256 bondedBalance = balanceOfBonded(account);

    if (bondedBalance == 0) {
      return;
    }

    uint256 lessStakePadding = (balanceOfStakePadding(account) * amount) /
      bondedBalance;

    _reconcileWithdrawn(account, amount, bondedBalance);
    _removeFromStakePadding(account, lessStakePadding);
    _afterUnbond(account, amount);
  }

  function _initialSetup(
    address _collateralToken,
    address _miningService,
    address _rewardProvider
  ) internal {
    _roleSetup(MINING_SERVICE_ROLE, _miningService);
    _roleSetup(REWARD_MANAGER_ROLE, _miningService);
    _roleSetup(REWARD_PROVIDER_ROLE, _rewardProvider);

    collateralToken = ERC20(_collateralToken);
    miningService = IMiningService(_miningService);
  }

  function _addRewardProviders(address[] memory accounts) internal {
    uint256 length = accounts.length;

    for (uint256 i; i < length; ++i) {
      _grantRole(REWARD_PROVIDER_ROLE, accounts[i]);
    }
  }

  function withdrawAll() external nonReentrant {
    uint256 rewardEarned = earned(msg.sender);

    _handleWithdrawForAccount(msg.sender, rewardEarned, msg.sender);
  }

  function withdraw(uint256 rewardAmount) external nonReentrant {
    uint256 rewardEarned = earned(msg.sender);

    require(rewardAmount <= rewardEarned, "< earned");

    _handleWithdrawForAccount(msg.sender, rewardAmount, msg.sender);
  }

  /*
   * METHODS TO OVERRIDE
   */
  function totalBonded() public view virtual returns (uint256);

  function valueOfBonded() public view virtual returns (uint256);

  function balanceOfBonded(address account)
    public
    view
    virtual
    returns (uint256);

  /*
   * totalReleasedReward and totalDeclaredReward will often be the same. However, in the case
   * of vesting rewards they are different. In that case totalDeclaredReward is total
   * reward, including unvested. totalReleasedReward is just the rewards that have completed
   * the vesting schedule.
   */
  function totalDeclaredReward() public view virtual returns (uint256);

  function totalReleasedReward() public view virtual returns (uint256) {
    return _globalReleased;
  }

  function releaseReward(uint256 amount)
    external
    virtual
    onlyRoleMalt(REWARD_PROVIDER_ROLE, "Only reward provider role")
  {
    _globalReleased += amount;
    require(
      collateralToken.balanceOf(address(this)) + _globalWithdrawn >=
        _globalReleased,
      "RewardAssertion"
    );
  }

  /*
   * PUBLIC VIEW FUNCTIONS
   */
  function totalStakePadding() public view returns (uint256) {
    return _globalStakePadding;
  }

  function balanceOfStakePadding(address account)
    public
    view
    returns (uint256)
  {
    return _userStakePadding[account];
  }

  function totalWithdrawn() public view returns (uint256) {
    return _globalWithdrawn;
  }

  function withdrawnBalance(address account) public view returns (uint256) {
    return _userWithdrawn[account];
  }

  function getRewardOwnershipFraction(address account)
    public
    view
    returns (uint256 numerator, uint256 denominator)
  {
    numerator = balanceOfRewards(account);
    denominator = totalDeclaredReward();
  }

  function balanceOfRewards(address account) public view returns (uint256) {
    /*
     * This represents the rewards allocated to a given account but does not
     * mean all these rewards are unlocked yet. The earned method will
     * fetch the balance that is unlocked for an account
     */
    uint256 balanceOfRewardedWithStakePadding = _getFullyPaddedReward(account);

    uint256 stakePaddingBalance = balanceOfStakePadding(account);

    if (balanceOfRewardedWithStakePadding > stakePaddingBalance) {
      return balanceOfRewardedWithStakePadding - stakePaddingBalance;
    }
    return 0;
  }

  function netRewardBalance(address account) public view returns (uint256) {
    uint256 rewards = balanceOfRewards(account);
    uint256 withdrawn = _userWithdrawn[account];

    if (rewards > withdrawn) {
      return rewards - withdrawn;
    }
    return 0;
  }

  function earned(address account)
    public
    view
    virtual
    returns (uint256 earnedReward)
  {
    (
      uint256 rewardNumerator,
      uint256 rewardDenominator
    ) = getRewardOwnershipFraction(account);

    if (rewardDenominator > 0) {
      earnedReward =
        (totalReleasedReward() * rewardNumerator) /
        rewardDenominator;

      if (earnedReward > _userWithdrawn[account]) {
        earnedReward -= _userWithdrawn[account];
      } else {
        earnedReward = 0;
      }
    }

    uint256 balance = collateralToken.balanceOf(address(this));

    if (earnedReward > balance) {
      earnedReward = balance;
    }
  }

  /*
   * INTERNAL VIEW FUNCTIONS
   */
  function _getFullyPaddedReward(address account)
    internal
    view
    returns (uint256)
  {
    uint256 globalBondedTotal = totalBonded();
    if (globalBondedTotal == 0) {
      return 0;
    }

    uint256 totalRewardedWithStakePadding = totalDeclaredReward() +
      totalStakePadding();

    return
      (totalRewardedWithStakePadding * balanceOfBonded(account)) /
      globalBondedTotal;
  }

  /*
   * INTERNAL FUNCTIONS
   */
  function _withdraw(
    address account,
    uint256 amountReward,
    address to
  ) internal {
    uint256 balance = collateralToken.balanceOf(address(this));

    if (amountReward > balance) {
      amountReward = balance;
    }

    _userWithdrawn[account] += amountReward;
    _globalWithdrawn += amountReward;
    collateralToken.safeTransfer(to, amountReward);

    emit Withdraw(account, amountReward, to);
  }

  function _handleStakePadding(address account, uint256 amount) internal {
    uint256 totalBonded = totalBonded();

    uint256 newStakePadding = totalBonded == 0
      ? totalDeclaredReward() == 0 ? amount * 1e6 : 0
      : ((totalDeclaredReward() + totalStakePadding()) * amount) / totalBonded;

    _addToStakePadding(account, newStakePadding);
  }

  function _addToStakePadding(address account, uint256 amount) internal {
    _userStakePadding[account] = _userStakePadding[account] + amount;

    _globalStakePadding = _globalStakePadding + amount;
  }

  function _removeFromStakePadding(address account, uint256 amount) internal {
    _userStakePadding[account] = _userStakePadding[account] - amount;

    _globalStakePadding = _globalStakePadding - amount;
  }

  function _reconcileWithdrawn(
    address account,
    uint256 amount,
    uint256 bondedBalance
  ) internal {
    uint256 withdrawDiff = (_userWithdrawn[account] * amount) / bondedBalance;
    _userWithdrawn[account] -= withdrawDiff;
    _globalWithdrawn -= withdrawDiff;
    _globalReleased -= withdrawDiff;
  }

  function _handleWithdrawForAccount(
    address account,
    uint256 rewardAmount,
    address to
  ) internal {
    _beforeWithdraw(account, rewardAmount);

    _withdraw(account, rewardAmount, to);

    _afterWithdraw(account, rewardAmount);
  }

  /*
   * HOOKS
   */
  function _beforeWithdraw(address account, uint256 amount) internal virtual {
    // hook
  }

  function _afterWithdraw(address account, uint256 amount) internal virtual {
    // hook
  }

  function _beforeBond(address account, uint256 amount) internal virtual {
    // hook
  }

  function _afterBond(address account, uint256 amount) internal virtual {
    // hook
  }

  function _beforeUnbond(address account, uint256 amount) internal virtual {
    // hook
  }

  function _afterUnbond(address account, uint256 amount) internal virtual {
    // hook
  }

  /*
   * PRIVILEDGED METHODS
   */
  function withdrawForAccount(
    address account,
    uint256 amount,
    address to
  )
    external
    onlyRoleMalt(REWARD_MANAGER_ROLE, "Must have reward manager privs")
    returns (uint256)
  {
    uint256 rewardEarned = earned(account);

    if (rewardEarned < amount) {
      amount = rewardEarned;
    }

    _handleWithdrawForAccount(account, amount, to);

    return amount;
  }

  function _beforeSetMiningService(address _miningService) internal override {
    _transferRole(_miningService, address(miningService), MINING_SERVICE_ROLE);
    _transferRole(_miningService, address(miningService), REWARD_MANAGER_ROLE);
  }

  function setPoolId(uint256 _poolId)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    poolId = _poolId;

    emit SetPoolId(_poolId);
  }
}
