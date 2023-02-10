// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../libraries/uniswap/Babylonian.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/SwingTraderExtension.sol";
import "../StabilizedPoolExtensions/DexHandlerExtension.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../StabilizedPoolExtensions/AuctionExtension.sol";
import "../interfaces/IAuction.sol";
import "../interfaces/IDexHandler.sol";
import "../interfaces/IMaltDataLab.sol";
import "../interfaces/IBurnMintableERC20.sol";

/// @title Liquidity Extension
/// @author 0xScotch <scotch@malt.money>
/// @notice In charge of facilitating a premium with net supply contraction during auctions
contract LiquidityExtension is
  StabilizedPoolUnit,
  SwingTraderExtension,
  DexHandlerExtension,
  DataLabExtension,
  AuctionExtension
{
  using SafeERC20 for ERC20;

  uint256 public minReserveRatioBps = 2500; // 25%

  event SetMinReserveRatio(uint256 ratio);
  event BurnMalt(uint256 purchased);
  event AllocateBurnBudget(uint256 amount);

  constructor(
    address timelock,
    address repository,
    address poolFactory
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {}

  function setupContracts(
    address _auction,
    address _collateralToken,
    address _malt,
    address _dexHandler,
    address _maltDataLab,
    address _swingTrader,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role") {
    require(!contractActive, "LE: Already setup");
    require(_auction != address(0), "LE: Auction addr(0)");
    require(_collateralToken != address(0), "LE: Col addr(0)");
    require(_malt != address(0), "LE: Malt addr(0)");
    require(_dexHandler != address(0), "LE: DexHandler addr(0)");
    require(_maltDataLab != address(0), "LE: DataLab addr(0)");
    require(_swingTrader != address(0), "LE: SwingTrader addr(0)");

    contractActive = true;

    _setupRole(AUCTION_ROLE, _auction);

    auction = IAuction(_auction);
    collateralToken = ERC20(_collateralToken);
    malt = IBurnMintableERC20(_malt);
    dexHandler = IDexHandler(_dexHandler);
    maltDataLab = IMaltDataLab(_maltDataLab);
    swingTrader = ISwingTrader(_swingTrader);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  /*
   * PUBLIC VIEW METHODS
   */
  function hasMinimumReserves() public view returns (bool) {
    (uint256 rRatio, uint256 decimals) = reserveRatio();
    return rRatio >= (minReserveRatioBps * (10**decimals)) / 10000;
  }

  function collateralDeficit()
    public
    view
    returns (uint256 deficit, uint256 decimals)
  {
    // Returns the amount of collateral token required to reach minimum reserves
    // Returns 0 if liquidity extension contains minimum reserves.
    uint256 balance = collateralToken.balanceOf(address(this));
    uint256 collateralDecimals = collateralToken.decimals();

    uint256 k = maltDataLab.smoothedK();

    if (k == 0) {
      (k, ) = maltDataLab.lastK();
      if (k == 0) {
        return (0, collateralDecimals);
      }
    }

    uint256 priceTarget = maltDataLab.priceTarget();

    uint256 fullCollateral = Babylonian.sqrt(
      (k * (10**collateralDecimals)) / priceTarget
    );

    uint256 minReserves = (fullCollateral * minReserveRatioBps) / 10000;

    if (minReserves > balance) {
      return (minReserves - balance, collateralDecimals);
    }

    return (0, collateralDecimals);
  }

  function reserveRatio() public view returns (uint256, uint256) {
    uint256 balance = collateralToken.balanceOf(address(this));
    uint256 collateralDecimals = collateralToken.decimals();

    uint256 k = maltDataLab.smoothedK();

    if (k == 0) {
      return (0, collateralDecimals);
    }

    uint256 priceTarget = maltDataLab.priceTarget();

    uint256 fullCollateral = Babylonian.sqrt(
      (k * (10**collateralDecimals)) / priceTarget
    );

    uint256 rRatio = (balance * (10**collateralDecimals)) / fullCollateral;
    return (rRatio, collateralDecimals);
  }

  function reserveRatioAverage(uint256 lookback)
    public
    view
    returns (uint256, uint256)
  {
    uint256 balance = collateralToken.balanceOf(address(this));
    uint256 collateralDecimals = collateralToken.decimals();

    uint256 k = maltDataLab.kAverage(lookback);
    uint256 priceTarget = maltDataLab.priceTarget();

    uint256 fullCollateral = Babylonian.sqrt(
      (k * (10**collateralDecimals)) / priceTarget
    );

    uint256 rRatio = (balance * (10**collateralDecimals)) / fullCollateral;
    return (rRatio, collateralDecimals);
  }

  /*
   * PRIVILEDGED METHODS
   */
  function purchaseAndBurn(uint256 amount)
    external
    onlyRoleMalt(AUCTION_ROLE, "Must have auction privs")
    onlyActive
    returns (uint256 purchased)
  {
    require(
      collateralToken.balanceOf(address(this)) >= amount,
      "LE: Insufficient balance"
    );
    collateralToken.safeTransfer(address(dexHandler), amount);
    purchased = dexHandler.buyMalt(amount, 10000); // 100% allowable slippage
    malt.burn(address(this), purchased);

    emit BurnMalt(purchased);
  }

  function allocateBurnBudget(uint256 amount)
    external
    onlyRoleMalt(AUCTION_ROLE, "Must have auction privs")
    onlyActive
    returns (uint256 purchased)
  {
    // Send the burnable amount to the swing trader so it can be used to burn more malt if required
    require(
      collateralToken.balanceOf(address(this)) >= amount,
      "LE: Insufficient balance"
    );
    collateralToken.safeTransfer(address(swingTrader), amount);

    emit AllocateBurnBudget(amount);
  }

  function setMinReserveRatio(uint256 _ratio)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_ratio != 0 && _ratio <= 10000, "Must be between 0 and 100");
    minReserveRatioBps = _ratio;
    emit SetMinReserveRatio(_ratio);
  }

  function _accessControl()
    internal
    override(
      SwingTraderExtension,
      DexHandlerExtension,
      DataLabExtension,
      AuctionExtension
    )
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
