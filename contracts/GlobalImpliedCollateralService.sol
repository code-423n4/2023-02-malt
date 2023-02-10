// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";

import "./Permissions.sol";
import "./StabilityPod/PoolCollateral.sol";

/// @title Global Implied Collateral Service
/// @author 0xScotch <scotch@malt.money>
/// @notice A contract that provides an abstraction above all implied collateral sources
contract GlobalImpliedCollateralService is Permissions {
  bytes32 public immutable UPDATER_MANAGER_ROLE;
  // Note that the values in CoreCollateral are all denominated in malt.decimals
  CoreCollateral public collateral;

  address internal immutable deployer;
  address public updaterManager;
  address public proposedManager;

  ERC20 public malt;

  mapping(address => address) public poolUpdaters;
  mapping(address => PoolCollateral) public poolCollateral;
  mapping(address => address) public poolUpdatersLookup;

  event SetPoolUpdater(address pool, address updater);
  event Sync(
    address indexed pool,
    uint256 total,
    uint256 overflow,
    uint256 liquidityExtension,
    uint256 swingTrader,
    uint256 swingTraderMalt,
    uint256 arbTokens
  );
  event SyncTotals(
    uint256 totalCollateral,
    uint256 totalRewardOverflow,
    uint256 totalLiquidityExtension,
    uint256 swingTraderCollateral,
    uint256 swingTraderMalt,
    uint256 arbTokens
  );

  event ChangeUpdaterManager(address manager);
  event ProposeUpdaterManager(address manager);

  constructor(
    address _repository,
    address initialAdmin,
    address _malt,
    address _deployer
  ) {
    require(_repository != address(0), "GlobImpCol: Timelock addr(0)");
    require(initialAdmin != address(0), "GlobImpCol: Admin addr(0)");
    require(_malt != address(0), "GlobImpCol: Malt addr(0)");
    _initialSetup(_repository);

    UPDATER_MANAGER_ROLE = 0x46a4238f90cacb5750da6fcead9da5df56c925da47001c1e8d3e05c0b5a42012;
    _roleSetup(
      0x46a4238f90cacb5750da6fcead9da5df56c925da47001c1e8d3e05c0b5a42012,
      initialAdmin
    );

    malt = ERC20(_malt);
    deployer = _deployer;
  }

  function totalPhantomMalt() external view returns (uint256) {
    // Represents the amount of Malt held by the protocol in an effectively burned state
    // This could potentially be more complex in the future
    return collateral.swingTraderMalt;
  }

  function collateralRatio() public view returns (uint256) {
    uint256 decimals = malt.decimals();
    uint256 totalSupply = malt.totalSupply();
    if (totalSupply == 0) {
      return 0;
    }
    return (collateral.total * (10**decimals)) / totalSupply;
  }

  function swingTraderCollateralRatio() public view returns (uint256) {
    uint256 decimals = malt.decimals();
    return (collateral.swingTrader * (10**decimals)) / malt.totalSupply();
  }

  function swingTraderCollateralDeficit() public view returns (uint256) {
    // Note that collateral.swingTrader is already denominated in malt.decimals()
    uint256 maltSupply = malt.totalSupply();
    uint256 collateral = collateral.swingTrader; // gas

    if (collateral >= maltSupply) {
      return 0;
    }

    return maltSupply - collateral;
  }

  function setPoolUpdater(address _pool, address _updater)
    external
    onlyRoleMalt(UPDATER_MANAGER_ROLE, "Must have updater manager role")
  {
    require(_updater != address(0), "GlobImpCol: No addr(0)");
    poolUpdaters[_updater] = _pool;
    address oldUpdater = poolUpdatersLookup[_pool];
    emit SetPoolUpdater(_pool, _updater);
    poolUpdaters[oldUpdater] = address(0);
    poolUpdatersLookup[_pool] = _updater;
  }

  function sync(PoolCollateral memory _pool) external {
    require(
      poolUpdaters[msg.sender] == _pool.lpPool,
      "GlobImpCol: Unknown pool"
    );

    PoolCollateral storage existingPool = poolCollateral[_pool.lpPool];

    uint256 existingCollateral = existingPool.total;

    uint256 total = collateral.total; // gas
    if (existingCollateral <= total) {
      total -= existingCollateral; // subtract existing value
    } else {
      total = 0;
    }

    uint256 swingTraderMalt = collateral.swingTraderMalt; // gas
    if (existingPool.swingTraderMalt <= swingTraderMalt) {
      swingTraderMalt -= existingPool.swingTraderMalt;
    } else {
      swingTraderMalt = 0;
    }

    uint256 swingTraderCollat = collateral.swingTrader; // gas
    if (existingPool.swingTrader <= swingTraderCollat) {
      swingTraderCollat -= existingPool.swingTrader;
    } else {
      swingTraderCollat = 0;
    }

    uint256 arb = collateral.arbTokens; // gas
    if (existingPool.arbTokens <= arb) {
      arb -= existingPool.arbTokens;
    } else {
      arb = 0;
    }

    uint256 overflow = collateral.rewardOverflow; // gas
    if (existingPool.rewardOverflow <= overflow) {
      overflow -= existingPool.rewardOverflow;
    } else {
      overflow = 0;
    }

    uint256 liquidityExtension = collateral.liquidityExtension; // gas
    if (existingPool.liquidityExtension <= liquidityExtension) {
      liquidityExtension -= existingPool.liquidityExtension;
    } else {
      liquidityExtension = 0;
    }

    total += _pool.total;
    swingTraderMalt += _pool.swingTraderMalt;
    swingTraderCollat += _pool.swingTrader;
    arb += _pool.arbTokens;
    overflow += _pool.rewardOverflow;
    liquidityExtension += _pool.liquidityExtension;

    // Update global collateral
    collateral.total = total;
    // Update global swing trader malt
    collateral.swingTraderMalt = swingTraderMalt;
    // Update global ST collateral
    collateral.swingTrader = swingTraderCollat;
    // Update global arb tokens
    collateral.arbTokens = arb;
    // Update global overflow
    collateral.rewardOverflow = overflow;
    // Update global liquidityExtension
    collateral.liquidityExtension = liquidityExtension;

    // Update PoolCollateral for this pool
    existingPool.lpPool = _pool.lpPool;
    existingPool.total = _pool.total;
    existingPool.rewardOverflow = _pool.rewardOverflow;
    existingPool.liquidityExtension = _pool.liquidityExtension;
    existingPool.swingTrader = _pool.swingTrader;
    existingPool.swingTraderMalt = _pool.swingTraderMalt;
    existingPool.arbTokens = _pool.arbTokens;

    emit Sync(
      existingPool.lpPool,
      existingPool.total,
      existingPool.rewardOverflow,
      existingPool.liquidityExtension,
      existingPool.swingTrader,
      existingPool.swingTraderMalt,
      existingPool.arbTokens
    );
    emit SyncTotals(
      total,
      overflow,
      liquidityExtension,
      swingTraderCollat,
      swingTraderMalt,
      arb
    );
  }

  /// @notice Privileged method for setting the initial updater manager
  /// @param _updaterManager The address of the new manager
  function setUpdaterManager(address _updaterManager) external {
    require(msg.sender == deployer, "Only deployer");
    require(_updaterManager != address(0), "Cannot use addr(0)");
    require(updaterManager == address(0), "Initial updater already set");
    updaterManager = _updaterManager;
    _grantRole(UPDATER_MANAGER_ROLE, _updaterManager);
  }

  /// @notice Privileged method for proposing a new updater manager
  /// @param _updaterManager The address of the newly proposed manager contract
  /// @dev Only callable via the existing updater manager contract
  function proposeNewUpdaterManager(address _updaterManager)
    external
    onlyRoleMalt(UPDATER_MANAGER_ROLE, "Must have updater manager role")
  {
    require(_updaterManager != address(0), "Cannot use addr(0)");
    proposedManager = _updaterManager;
    emit ProposeUpdaterManager(_updaterManager);
  }

  /// @notice Method for a proposed updater manager contract to accept the role
  /// @dev Only callable via the proposedManager
  function acceptUpdaterManagerRole() external {
    require(msg.sender == proposedManager, "Must be proposedManager");
    _transferRole(proposedManager, updaterManager, UPDATER_MANAGER_ROLE);
    proposedManager = address(0);
    updaterManager = msg.sender;
    emit ChangeUpdaterManager(msg.sender);
  }
}
