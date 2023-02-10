// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../StabilizedPoolExtensions/StabilizerNodeExtension.sol";
import "../interfaces/ISwingTrader.sol";
import "../interfaces/IMaltDataLab.sol";

struct SwingTraderData {
  uint256 id;
  uint256 index; // index into the activeTraders array
  address traderContract;
  string name;
  bool active;
}

/// @title Swing Trader Manager
/// @author 0xScotch <scotch@malt.money>
/// @notice The contract simply orchestrates SwingTrader instances. Initially there will only be a single
/// Swing Trader. But over time there may be others with different strategies that can be balanced / orchestrated
/// by this contract.
contract SwingTraderManager is
  StabilizedPoolUnit,
  ISwingTrader,
  DataLabExtension,
  StabilizerNodeExtension
{
  using SafeERC20 for ERC20;

  bytes32 public immutable CAPITAL_DELEGATE_ROLE;
  bytes32 public immutable MANAGER_ROLE;

  mapping(uint256 => SwingTraderData) public swingTraders;
  uint256[] public activeTraders;
  uint256 public totalProfit;
  uint256 public dustThreshold = 1e18; // $1

  event ToggleTraderActive(uint256 traderId, bool active);
  event AddSwingTrader(
    uint256 traderId,
    string name,
    bool active,
    address swingTrader
  );
  event Delegation(uint256 amount, address destination, address delegate);
  event BuyMalt(uint256 capitalUsed);
  event SellMalt(uint256 amountSold, uint256 profit);
  event SetDustThreshold(uint256 threshold);

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
    address _stabilizerNode,
    address _maltDataLab,
    address _swingTrader,
    address _rewardOverflow,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Only pool factory role") {
    require(!contractActive, "SwingTraderManager: Already setup");
    require(
      _collateralToken != address(0),
      "SwingTraderManager: ColToken addr(0)"
    );
    require(_malt != address(0), "SwingTraderManager: Malt addr(0)");
    require(
      _stabilizerNode != address(0),
      "SwingTraderManager: StabNode addr(0)"
    );
    require(
      _maltDataLab != address(0),
      "SwingTraderManager: MaltDataLab addr(0)"
    );
    require(
      _swingTrader != address(0),
      "SwingTraderManager: SwingTrader addr(0)"
    );
    require(
      _rewardOverflow != address(0),
      "SwingTraderManager: Overflow addr(0)"
    );

    contractActive = true;

    _setupRole(STABILIZER_NODE_ROLE, _stabilizerNode);

    collateralToken = ERC20(_collateralToken);
    malt = IBurnMintableERC20(_malt);
    maltDataLab = IMaltDataLab(_maltDataLab);
    stabilizerNode = IStabilizerNode(_stabilizerNode);

    // Internal SwingTrader
    swingTraders[1] = SwingTraderData({
      id: 1,
      index: 0,
      traderContract: _swingTrader,
      name: "CoreSwingTrader",
      active: true
    });
    activeTraders.push(1);

    // RewardOverflow is secondary swing trader
    swingTraders[2] = SwingTraderData({
      id: 2,
      index: 1,
      traderContract: _rewardOverflow,
      name: "CoreSwingTrader",
      active: true
    });

    activeTraders.push(2);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function _beforeSetStabilizerNode(address _stabilizerNode) internal override {
    _transferRole(
      _stabilizerNode,
      address(stabilizerNode),
      STABILIZER_NODE_ROLE
    );
  }

  function buyMalt(uint256 maxCapital)
    external
    onlyRoleMalt(STABILIZER_NODE_ROLE, "Must have stabilizer node privs")
    onlyActive
    returns (uint256 capitalUsed)
  {
    if (maxCapital == 0) {
      return 0;
    }
    uint256[] memory traderIds = activeTraders;
    uint256 length = traderIds.length;

    uint256 totalCapital;
    uint256[] memory traderCapital = new uint256[](length);

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];

      if (!trader.active) {
        continue;
      }

      uint256 traderBalance = collateralToken.balanceOf(trader.traderContract);
      totalCapital += traderBalance;
      traderCapital[i] = traderBalance;
    }

    if (totalCapital == 0) {
      return 0;
    }

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];
      uint256 share = (maxCapital * traderCapital[i]) / totalCapital;

      if (share == 0) {
        continue;
      }

      if (capitalUsed + share > maxCapital) {
        share = maxCapital - capitalUsed;
      }

      uint256 used = ISwingTrader(trader.traderContract).buyMalt(share);
      capitalUsed += used;

      if (capitalUsed >= maxCapital) {
        break;
      }
    }

    emit BuyMalt(capitalUsed);

    return capitalUsed;
  }

  function sellMalt(uint256 maxAmount)
    external
    onlyRoleMalt(STABILIZER_NODE_ROLE, "Must have stabilizer node privs")
    onlyActive
    returns (uint256 amountSold)
  {
    uint256[] memory traderIds = activeTraders;
    uint256 length = traderIds.length;
    uint256 profit;

    uint256 totalMalt;
    uint256[] memory traderMalt = new uint256[](length);

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];

      if (!trader.active) {
        continue;
      }

      uint256 traderMaltBalance = malt.balanceOf(trader.traderContract);
      totalMalt += traderMaltBalance;
      traderMalt[i] = traderMaltBalance;
    }

    if (totalMalt == 0) {
      return 0;
    }

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];
      uint256 share = (maxAmount * traderMalt[i]) / totalMalt;

      if (share == 0) {
        continue;
      }

      if (amountSold + share > maxAmount) {
        share = maxAmount - amountSold;
      }

      uint256 initialProfit = ISwingTrader(trader.traderContract).totalProfit();
      try ISwingTrader(trader.traderContract).sellMalt(share) returns (
        uint256 sold
      ) {
        uint256 finalProfit = ISwingTrader(trader.traderContract).totalProfit();
        profit += (finalProfit - initialProfit);
        amountSold += sold;
      } catch {
        // if it fails just continue
      }

      if (amountSold >= maxAmount) {
        break;
      }
    }

    if (amountSold + dustThreshold >= maxAmount) {
      return maxAmount;
    }

    totalProfit += profit;

    emit SellMalt(amountSold, profit);
  }

  function costBasis() public view returns (uint256 cost, uint256 decimals) {
    uint256[] memory traderIds = activeTraders;
    uint256 length = traderIds.length;
    decimals = collateralToken.decimals();

    uint256 totalMaltBalance;
    uint256 totalDeployedCapital;

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];
      totalDeployedCapital += ISwingTrader(trader.traderContract)
        .deployedCapital();
      totalMaltBalance += malt.balanceOf(trader.traderContract);
    }

    if (totalDeployedCapital == 0 || totalMaltBalance == 0) {
      return (0, decimals);
    }

    totalMaltBalance = maltDataLab.maltToRewardDecimals(totalMaltBalance);

    return (
      (totalDeployedCapital * (10**decimals)) / totalMaltBalance,
      decimals
    );
  }

  function calculateSwingTraderMaltRatio()
    public
    view
    returns (uint256 maltRatio)
  {
    uint256[] memory traderIds = activeTraders;
    uint256 length = traderIds.length;
    uint256 decimals = collateralToken.decimals();
    uint256 maltDecimals = malt.decimals();
    uint256 totalMaltBalance;
    uint256 totalCollateralBalance;

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];
      totalMaltBalance += malt.balanceOf(trader.traderContract);
      totalCollateralBalance += collateralToken.balanceOf(
        trader.traderContract
      );
    }

    totalMaltBalance = maltDataLab.maltToRewardDecimals(totalMaltBalance);

    uint256 stMaltValue = ((totalMaltBalance * maltDataLab.priceTarget()) /
      (10**decimals));

    uint256 netBalance = totalCollateralBalance + stMaltValue;

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
    uint256[] memory traderIds = activeTraders;
    uint256 length = traderIds.length;

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];
      maltBalance += malt.balanceOf(trader.traderContract);
      collateralBalance += collateralToken.balanceOf(trader.traderContract);
    }
  }

  function delegateCapital(uint256 amount, address destination)
    external
    onlyRoleMalt(CAPITAL_DELEGATE_ROLE, "Must have capital delegation privs")
    onlyActive
  {
    uint256[] memory traderIds = activeTraders;
    uint256 length = traderIds.length;

    uint256 totalCapital;
    uint256[] memory traderCapital = new uint256[](length);

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];

      if (!trader.active) {
        continue;
      }

      uint256 traderBalance = collateralToken.balanceOf(trader.traderContract);
      totalCapital += traderBalance;
      traderCapital[i] = traderBalance;
    }

    if (totalCapital == 0) {
      return;
    }

    uint256 capitalUsed;

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];
      uint256 share = (amount * traderCapital[i]) / totalCapital;

      if (capitalUsed + share > amount) {
        share = amount - capitalUsed;
      }

      if (share == 0) {
        continue;
      }

      capitalUsed += share;
      ISwingTrader(trader.traderContract).delegateCapital(share, destination);
    }

    emit Delegation(amount, destination, msg.sender);
  }

  function deployedCapital() external view returns (uint256 deployed) {
    uint256[] memory traderIds = activeTraders;
    uint256 length = traderIds.length;

    for (uint256 i; i < length; ++i) {
      SwingTraderData memory trader = swingTraders[activeTraders[i]];
      deployed += ISwingTrader(trader.traderContract).deployedCapital();
    }

    return deployed;
  }

  function addSwingTrader(
    uint256 traderId,
    address _swingTrader,
    bool active,
    string calldata name
  ) external onlyRoleMalt(ADMIN_ROLE, "Must have admin privs") {
    SwingTraderData storage trader = swingTraders[traderId];
    require(traderId > 2 && trader.id == 0, "TraderId already used");
    require(_swingTrader != address(0), "addr(0)");

    swingTraders[traderId] = SwingTraderData({
      id: traderId,
      index: activeTraders.length,
      traderContract: _swingTrader,
      name: name,
      active: active
    });

    activeTraders.push(traderId);

    emit AddSwingTrader(traderId, name, active, _swingTrader);
  }

  function toggleTraderActive(uint256 traderId)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    SwingTraderData storage trader = swingTraders[traderId];
    require(trader.id == traderId, "Unknown trader");

    bool active = !trader.active;
    trader.active = active;

    if (active) {
      // setting it to active so add to activeTraders
      trader.index = activeTraders.length;
      activeTraders.push(traderId);
    } else {
      // Becoming inactive so remove from activePools
      uint256 index = trader.index;
      uint256 lastTrader = activeTraders[activeTraders.length - 1];

      activeTraders[index] = lastTrader;
      activeTraders.pop();

      swingTraders[lastTrader].index = index;
      trader.index = 0;
    }

    emit ToggleTraderActive(traderId, active);
  }

  function setDustThreshold(uint256 _dust)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    dustThreshold = _dust;
    emit SetDustThreshold(_dust);
  }

  function _accessControl()
    internal
    override(DataLabExtension, StabilizerNodeExtension)
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
