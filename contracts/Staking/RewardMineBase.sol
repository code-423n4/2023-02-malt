// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "./AbstractRewardMine.sol";
import "../interfaces/IDistributor.sol";
import "../interfaces/IBonding.sol";
import "../StabilizedPoolExtensions/BondingExtension.sol";

/// @title Reward Mine Base
/// @author 0xMojo7
/// @notice An implementation of AbstractRewardMine to accept rewards.
contract RewardMineBase is AbstractRewardMine, BondingExtension {
  using SafeERC20 for IERC20;

  IERC20 public lpToken;
  IDistributor public linearDistributor;

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
    address _distributor,
    address _bonding,
    address _collateralToken,
    address _lpToken
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role") {
    require(!contractActive, "RewardBase: Already setup");
    require(_miningService != address(0), "RewardBase: MiningSvc addr(0)");
    require(_distributor != address(0), "RewardBase: Distributor addr(0)");
    require(_bonding != address(0), "RewardBase: Bonding addr(0)");
    require(_lpToken != address(0), "RewardBase: lpToken addr(0)");
    require(_collateralToken != address(0), "RewardBase: RewardToken addr(0)");

    contractActive = true;

    bonding = IBonding(_bonding);
    lpToken = IERC20(_lpToken);
    linearDistributor = IDistributor(_distributor);

    _initialSetup(_collateralToken, _miningService, _distributor);

    (, address updater, ) = poolFactory.getPool(_lpToken);
    _setPoolUpdater(updater);
  }

  function onUnbond(address account, uint256 amount)
    external
    override
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

    // A full withdraw happens before this method is called.
    // So we can safely say _userWithdrawn is in fact all of the
    // currently vested rewards for the bonded LP
    uint256 declaredRewardDecrease = (_userWithdrawn[account] * amount) /
      bondedBalance;

    if (declaredRewardDecrease > 0) {
      linearDistributor.decrementRewards(declaredRewardDecrease);
    }

    uint256 lessStakePadding = (balanceOfStakePadding(account) * amount) /
      bondedBalance;

    _reconcileWithdrawn(account, amount, bondedBalance);
    _removeFromStakePadding(account, lessStakePadding);
    _afterUnbond(account, amount);
  }

  /*
   * MASTER CHEF FUNCTIONS
   */
  function deposit(uint256 _amount) external {
    require(msg.sender != address(0), "Depositer cannot be addr(0)");
    lpToken.safeTransferFrom(msg.sender, address(this), _amount);
    lpToken.safeApprove(address(bonding), _amount);
    bonding.bondToAccount(msg.sender, poolId, _amount);
    lpToken.safeApprove(address(bonding), 0);
  }

  function userInfo(address _user)
    external
    view
    returns (uint256 balanceBonded, uint256 balanceStakePadding)
  {
    balanceBonded = balanceOfBonded(_user);
    balanceStakePadding = balanceOfStakePadding(_user);
  }

  function pending(address _user) external view returns (uint256) {
    return earned(_user);
  }

  /*
   * PUBLIC VIEW FUNCTIONS
   */

  function totalDeclaredReward() public view override returns (uint256) {
    return _globalReleased;
  }

  function totalBonded() public view virtual override returns (uint256) {
    return bonding.totalBondedByPool(poolId);
  }

  function valueOfBonded() public view virtual override returns (uint256) {
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

  function _accessControl()
    internal
    override(MiningServiceExtension, BondingExtension)
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }

  function setLinearDistributor(address _distributor)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_distributor != address(0), "No addr(0)");
    linearDistributor = IDistributor(_distributor);
  }
}
