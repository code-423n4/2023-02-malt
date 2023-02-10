// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/SwingTraderExtension.sol";

/// @title Forfeit Handler
/// @author 0xScotch <scotch@malt.money>
/// @notice When a user unbonds, their unvested rewards are forfeited. This contract decides what to do with those funds
contract ForfeitHandler is StabilizedPoolUnit, SwingTraderExtension {
  using SafeERC20 for ERC20;

  address public treasury;

  uint256 public swingTraderRewardCutBps = 5000;

  event Forfeit(address sender, uint256 amount);
  event SetRewardCut(uint256 swingTraderCut);
  event SetTreasury(address treasury);

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    address _treasury
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    require(_treasury != address(0), "ForfeitHandler: Treasury addr(0)");

    treasury = _treasury;
  }

  function setupContracts(
    address _collateralToken,
    address _swingTrader,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role") {
    require(!contractActive, "ForfeitHandler: Already setup");
    require(_collateralToken != address(0), "ForfeitHandler: Col addr(0)");

    contractActive = true;

    collateralToken = ERC20(_collateralToken);
    swingTrader = ISwingTrader(_swingTrader);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function handleForfeit() external onlyActive {
    uint256 balance = collateralToken.balanceOf(address(this));

    if (balance == 0) {
      return;
    }

    uint256 swingTraderCut = (balance * swingTraderRewardCutBps) / 10000;
    uint256 treasuryCut = balance - swingTraderCut;

    if (swingTraderCut > 0) {
      collateralToken.safeTransfer(address(swingTrader), swingTraderCut);
    }

    if (treasuryCut > 0) {
      collateralToken.safeTransfer(treasury, treasuryCut);
    }

    emit Forfeit(msg.sender, balance);
  }

  /*
   * PRIVILEDGED METHODS
   */
  function setRewardCut(uint256 _swingTraderCut)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_swingTraderCut <= 10000, "Reward cut must add to 100%");

    swingTraderRewardCutBps = _swingTraderCut;

    emit SetRewardCut(_swingTraderCut);
  }

  function setTreasury(address _treasury)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role")
  {
    require(_treasury != address(0), "Cannot set 0 address");

    treasury = _treasury;

    emit SetTreasury(_treasury);
  }

  function _accessControl() internal override(SwingTraderExtension) {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
