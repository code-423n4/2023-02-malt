// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../StabilizedPoolExtensions/ProfitDistributorExtension.sol";
import "../StabilizedPoolExtensions/DexHandlerExtension.sol";
import "../StabilizedPoolExtensions/SwingTraderManagerExtension.sol";
import "../libraries/SafeBurnMintableERC20.sol";

/// @title Swing Trader
/// @author 0xScotch <scotch@malt.money>
/// @notice The sole aim of this contract is to defend peg and try to profit in the process.
/// @dev It does so from a privileged internal position where it is allowed to purchase on the AMM even in recovery mode
contract SwingTrader is
  StabilizedPoolUnit,
  DataLabExtension,
  ProfitDistributorExtension,
  DexHandlerExtension,
  SwingTraderManagerExtension
{
  using SafeERC20 for ERC20;
  using SafeBurnMintableERC20 for IBurnMintableERC20;

  bytes32 public immutable CAPITAL_DELEGATE_ROLE;
  bytes32 public immutable MANAGER_ROLE;

  uint256 public deployedCapital;
  uint256 public totalProfit;

  event Delegation(uint256 amount, address destination, address delegate);
  event BuyMalt(uint256 amount);
  event SellMalt(uint256 amount, uint256 profit);

  constructor(
    address timelock,
    address repository,
    address poolFactory
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    CAPITAL_DELEGATE_ROLE = 0x6b525fb9eaf138d3dc2ac8323126c54cad39e34e800f9605cb60df858920b17b;
    MANAGER_ROLE = 0x241ecf16d79d0f8dbfb92cbc07fe17840425976cf0667f022fe9877caa831b08;
    _roleSetup(
      0x6b525fb9eaf138d3dc2ac8323126c54cad39e34e800f9605cb60df858920b17b,
      timelock
    );
  }

  function setupContracts(
    address _collateralToken,
    address _malt,
    address _dexHandler,
    address _swingTraderManager,
    address _maltDataLab,
    address _profitDistributor,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Only pool factory role") {
    require(!contractActive, "SwingTrader: Already setup");

    require(_collateralToken != address(0), "SwingTrader: ColToken addr(0)");
    require(_malt != address(0), "SwingTrader: Malt addr(0)");
    require(_dexHandler != address(0), "SwingTrader: DexHandler addr(0)");
    require(_swingTraderManager != address(0), "SwingTrader: Manager addr(0)");
    require(_maltDataLab != address(0), "SwingTrader: MaltDataLab addr(0)");

    contractActive = true;

    _setupRole(MANAGER_ROLE, _swingTraderManager);

    _setupRole(CAPITAL_DELEGATE_ROLE, _swingTraderManager);

    collateralToken = ERC20(_collateralToken);
    malt = IBurnMintableERC20(_malt);
    dexHandler = IDexHandler(_dexHandler);
    maltDataLab = IMaltDataLab(_maltDataLab);
    profitDistributor = IProfitDistributor(_profitDistributor);
    swingTraderManager = ISwingTrader(_swingTraderManager);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function _beforeSetSwingTraderManager(address _swingTraderManager)
    internal
    override
  {
    _transferRole(
      _swingTraderManager,
      address(swingTraderManager),
      MANAGER_ROLE
    );
    _transferRole(
      _swingTraderManager,
      address(swingTraderManager),
      CAPITAL_DELEGATE_ROLE
    );
  }

  function buyMalt(uint256 maxCapital)
    external
    onlyRoleMalt(MANAGER_ROLE, "Must have swing trader manager privs")
    onlyActive
    returns (uint256 capitalUsed)
  {
    if (maxCapital == 0) {
      return 0;
    }

    uint256 balance = collateralToken.balanceOf(address(this));

    if (balance == 0) {
      return 0;
    }

    if (maxCapital < balance) {
      balance = maxCapital;
    }

    collateralToken.safeTransfer(address(dexHandler), balance);
    dexHandler.buyMalt(balance, 10000); // 100% allowable slippage

    deployedCapital = deployedCapital + balance;

    emit BuyMalt(balance);

    return balance;
  }

  function sellMalt(uint256 maxAmount)
    external
    onlyRoleMalt(MANAGER_ROLE, "Must have swing trader manager privs")
    onlyActive
    returns (uint256 amountSold)
  {
    if (maxAmount == 0) {
      return 0;
    }

    uint256 totalMaltBalance = malt.balanceOf(address(this));

    if (totalMaltBalance == 0) {
      return 0;
    }

    (uint256 basis, ) = costBasis();

    if (maxAmount > totalMaltBalance) {
      maxAmount = totalMaltBalance;
    }

    malt.safeTransfer(address(dexHandler), maxAmount);
    uint256 rewards = dexHandler.sellMalt(maxAmount, 10000);

    uint256 deployed = deployedCapital; // gas

    if (rewards <= deployed && maxAmount < totalMaltBalance) {
      // If all malt is spent we want to reset deployed capital
      deployedCapital = deployed - rewards;
    } else {
      deployedCapital = 0;
    }

    uint256 profit = _calculateProfit(basis, maxAmount, rewards);

    _handleProfitDistribution(profit);

    totalProfit += profit;

    emit SellMalt(maxAmount, profit);

    return maxAmount;
  }

  function _handleProfitDistribution(uint256 profit) internal virtual {
    if (profit != 0) {
      collateralToken.safeTransfer(address(profitDistributor), profit);
      profitDistributor.handleProfit(profit);
    }
  }

  function costBasis() public view returns (uint256 cost, uint256 decimals) {
    // Always returns using the decimals of the collateralToken as that is the
    // currency costBasis is calculated in
    decimals = collateralToken.decimals();
    uint256 maltBalance = maltDataLab.maltToRewardDecimals(
      malt.balanceOf(address(this))
    );
    uint256 deployed = deployedCapital; // gas

    if (deployed == 0 || maltBalance == 0) {
      return (0, decimals);
    }

    return ((deployed * (10**decimals)) / maltBalance, decimals);
  }

  function _calculateProfit(
    uint256 costBasis,
    uint256 soldAmount,
    uint256 recieved
  ) internal returns (uint256 profit) {
    if (costBasis == 0) {
      return 0;
    }
    uint256 decimals = collateralToken.decimals();
    uint256 maltDecimals = malt.decimals();
    soldAmount = maltDataLab.maltToRewardDecimals(soldAmount);
    uint256 soldBasis = (costBasis * soldAmount) / (10**decimals);

    require(recieved > soldBasis, "Not profitable trade");
    profit = recieved - soldBasis;
  }

  function calculateSwingTraderMaltRatio()
    external
    view
    returns (uint256 maltRatio)
  {
    uint256 decimals = collateralToken.decimals();
    uint256 maltDecimals = malt.decimals();

    uint256 stCollateralBalance = collateralToken.balanceOf(address(this));
    uint256 stMaltBalance = maltDataLab.maltToRewardDecimals(
      malt.balanceOf(address(this))
    );

    uint256 stMaltValue = (stMaltBalance * maltDataLab.priceTarget()) /
      (10**decimals);

    uint256 netBalance = stCollateralBalance + stMaltValue;

    if (netBalance > 0) {
      maltRatio = ((stMaltValue * (10**decimals)) / netBalance);
    } else {
      maltRatio = 0;
    }
  }

  function getTokenBalances()
    external
    view
    returns (uint256 maltBalance, uint256 collateralBalance)
  {
    maltBalance = malt.balanceOf(address(this));
    collateralBalance = collateralToken.balanceOf(address(this));
  }

  function delegateCapital(uint256 amount, address destination)
    external
    onlyRoleMalt(CAPITAL_DELEGATE_ROLE, "Must have capital delegation privs")
    onlyActive
  {
    collateralToken.safeTransfer(destination, amount);
    emit Delegation(amount, destination, msg.sender);
  }

  function _accessControl()
    internal
    virtual
    override(
      DataLabExtension,
      ProfitDistributorExtension,
      DexHandlerExtension,
      SwingTraderManagerExtension
    )
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
