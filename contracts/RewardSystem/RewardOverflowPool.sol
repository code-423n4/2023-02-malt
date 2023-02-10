// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilityPod/SwingTrader.sol";
import "../StabilizedPoolExtensions/RewardThrottleExtension.sol";

/// @title Reward Overflow Pool
/// @author 0xScotch <scotch@malt.money>
/// @notice Allows throttler contract to request capital when the current epoch underflows desired reward
contract RewardOverflowPool is SwingTrader, RewardThrottleExtension {
  using SafeERC20 for ERC20;

  uint256 public maxFulfillmentBps = 5000; // 50%

  event FulfilledRequest(uint256 amount);
  event SetMaxFulfillment(uint256 maxBps);

  constructor(
    address timelock,
    address repository,
    address poolFactory
  ) SwingTrader(timelock, repository, poolFactory) {}

  function setupContracts(
    address _collateralToken,
    address _malt,
    address _dexHandler,
    address _swingTraderManager,
    address _maltDataLab,
    address _profitDistributor,
    address _rewardThrottle,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Only pool factory role") {
    require(!contractActive, "Overflow: Already setup");

    require(_collateralToken != address(0), "Overflow: ColToken addr(0)");
    require(_malt != address(0), "Overflow: Malt addr(0)");
    require(_dexHandler != address(0), "Overflow: DexHandler addr(0)");
    require(_swingTraderManager != address(0), "Overflow: Manager addr(0)");
    require(_maltDataLab != address(0), "Overflow: MaltDataLab addr(0)");
    require(_rewardThrottle != address(0), "Overflow: RewardThrottle addr(0)");

    contractActive = true;

    _setupRole(MANAGER_ROLE, _swingTraderManager);

    _setupRole(CAPITAL_DELEGATE_ROLE, _swingTraderManager);
    _setupRole(REWARD_THROTTLE_ROLE, _rewardThrottle);

    collateralToken = ERC20(_collateralToken);
    malt = IBurnMintableERC20(_malt);
    dexHandler = IDexHandler(_dexHandler);
    maltDataLab = IMaltDataLab(_maltDataLab);
    profitDistributor = IProfitDistributor(_profitDistributor);
    rewardThrottle = IRewardThrottle(_rewardThrottle);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function requestCapital(uint256 amount)
    external
    onlyRoleMalt(REWARD_THROTTLE_ROLE, "Must have Reward throttle privs")
    onlyActive
    returns (uint256 fulfilledAmount)
  {
    uint256 balance = collateralToken.balanceOf(address(this));

    if (balance == 0) {
      return 0;
    }

    // This is the max amount allowable
    fulfilledAmount = (balance * maxFulfillmentBps) / 10000;

    if (amount <= fulfilledAmount) {
      fulfilledAmount = amount;
    }

    collateralToken.safeTransfer(address(rewardThrottle), fulfilledAmount);

    emit FulfilledRequest(fulfilledAmount);

    return fulfilledAmount;
  }

  /*
   * PRIVILEDGED FUNCTIONS
   */
  function setMaxFulfillment(uint256 _maxFulfillment)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_maxFulfillment != 0, "Can't have 0 max fulfillment");
    require(_maxFulfillment <= 10000, "Can't have above 100% max fulfillment");

    maxFulfillmentBps = _maxFulfillment;
    emit SetMaxFulfillment(_maxFulfillment);
  }

  function _beforeSetRewardThrottle(address _rewardThrottle) internal override {
    _transferRole(
      _rewardThrottle,
      address(rewardThrottle),
      REWARD_THROTTLE_ROLE
    );
  }

  function _accessControl()
    internal
    override(SwingTrader, RewardThrottleExtension)
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
