// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../Permissions.sol";
import "../interfaces/IBurnMintableERC20.sol";
import "../libraries/uniswap/IUniswapV2Pair.sol";
import "../interfaces/IStabilizedPoolFactory.sol";

/// @title Pool Unit
/// @author 0xScotch <scotch@malt.money>
/// @notice An abstract contract inherited by all contracts that are part of a stabilized pool deployment
/// @dev This helps reduce boilerplate across the codebase declaring all the other contracts in the pool
abstract contract StabilizedPoolUnit is Permissions {
  bytes32 public immutable POOL_FACTORY_ROLE;
  bytes32 public immutable POOL_UPDATER_ROLE;
  bytes32 public immutable STABILIZER_NODE_ROLE;
  bytes32 public immutable LIQUIDITY_MINE_ROLE;
  bytes32 public immutable AUCTION_ROLE;
  bytes32 public immutable REWARD_THROTTLE_ROLE;

  bool internal contractActive;

  /* Permanent Members */
  IBurnMintableERC20 public malt;
  ERC20 public collateralToken;
  IUniswapV2Pair public stakeToken;

  /* Updatable */
  IStabilizedPoolFactory public poolFactory;

  event SetPoolUpdater(address updater);

  constructor(
    address _timelock,
    address _repository,
    address _poolFactory
  ) {
    require(_timelock != address(0), "Timelock addr(0)");
    require(_repository != address(0), "Repo addr(0)");
    _initialSetup(_repository);

    POOL_FACTORY_ROLE = 0x598cee9ad6a01a66130d639a08dbc750d4a51977e842638d2fc97de81141dc74;
    POOL_UPDATER_ROLE = 0xb70e81d43273d7b57d823256e2fd3d6bb0b670e5f5e1253ffd1c5f776a989c34;
    STABILIZER_NODE_ROLE = 0x9aebf7c4e2f9399fa54d66431d5afb53d5ce943832be8ebbced058f5450edf1b;
    LIQUIDITY_MINE_ROLE = 0xb8fddb29c347bbf5ee0bb24db027d53d603215206359b1142519846b9c87707f;
    AUCTION_ROLE = 0xc5e2d1653feba496cf5ce3a744b90ea18acf0df3d036aba9b2f85992a1467906;
    REWARD_THROTTLE_ROLE = 0x0beda4984192b677bceea9b67542fab864a133964c43188171c1c68a84cd3514;
    _roleSetup(
      0x598cee9ad6a01a66130d639a08dbc750d4a51977e842638d2fc97de81141dc74,
      _poolFactory
    );
    _setupRole(
      0x598cee9ad6a01a66130d639a08dbc750d4a51977e842638d2fc97de81141dc74,
      _timelock
    );
    _roleSetup(
      0x9aebf7c4e2f9399fa54d66431d5afb53d5ce943832be8ebbced058f5450edf1b,
      _timelock
    );
    _roleSetup(
      0xb8fddb29c347bbf5ee0bb24db027d53d603215206359b1142519846b9c87707f,
      _timelock
    );
    _roleSetup(
      0xc5e2d1653feba496cf5ce3a744b90ea18acf0df3d036aba9b2f85992a1467906,
      _timelock
    );
    _roleSetup(
      0x0beda4984192b677bceea9b67542fab864a133964c43188171c1c68a84cd3514,
      _timelock
    );

    poolFactory = IStabilizedPoolFactory(_poolFactory);
  }

  function setPoolUpdater(address _updater)
    internal
    onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role")
  {
    _setPoolUpdater(_updater);
  }

  function _setPoolUpdater(address _updater) internal {
    require(_updater != address(0), "Cannot use addr(0)");
    _grantRole(POOL_UPDATER_ROLE, _updater);
    emit SetPoolUpdater(_updater);
  }

  modifier onlyActive() {
    require(contractActive, "Contract not active");
    _;
  }
}
