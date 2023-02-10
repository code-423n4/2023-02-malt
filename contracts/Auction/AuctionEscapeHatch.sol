// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/Math.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/AuctionExtension.sol";
import "../StabilizedPoolExtensions/DexHandlerExtension.sol";
import "../interfaces/IAuction.sol";
import "../interfaces/IDexHandler.sol";
import "../interfaces/IBurnMintableERC20.sol";
import "./Auction.sol";

struct EarlyExitData {
  uint256 exitedEarly;
  uint256 earlyExitReturn;
  uint256 maltUsed;
}

struct AuctionExits {
  uint256 exitedEarly;
  uint256 earlyExitReturn;
  uint256 maltUsed;
  mapping(address => EarlyExitData) accountExits;
}

/// @title Auction Escape Hatch
/// @author 0xScotch <scotch@malt.money>
/// @notice Functionality to reduce risk profile of holding arbitrage tokens by allowing early exit
contract AuctionEscapeHatch is
  StabilizedPoolUnit,
  AuctionExtension,
  DexHandlerExtension
{
  using SafeERC20 for ERC20;

  uint256 public maxEarlyExitBps = 2000; // 20%
  uint256 public cooloffPeriod = 60 * 60 * 24; // 24 hours

  mapping(uint256 => AuctionExits) internal auctionEarlyExits;

  event EarlyExit(address account, uint256 amount, uint256 received);
  event SetEarlyExitBps(uint256 earlyExitBps);
  event SetCooloffPeriod(uint256 period);

  constructor(
    address timelock,
    address repository,
    address poolFactory
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {}

  function setupContracts(
    address _malt,
    address _collateralToken,
    address _auction,
    address _dexHandler,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must be pool factory") {
    require(!contractActive, "EscapeHatch: Already setup");
    require(_malt != address(0), "EscapeHatch: Malt addr(0)");
    require(_collateralToken != address(0), "EscapeHatch: Col addr(0)");
    require(_auction != address(0), "EscapeHatch: Auction addr(0)");
    require(_dexHandler != address(0), "EscapeHatch: DexHandler addr(0)");

    contractActive = true;

    malt = IBurnMintableERC20(_malt);
    collateralToken = ERC20(_collateralToken);
    auction = IAuction(_auction);
    dexHandler = IDexHandler(_dexHandler);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function exitEarly(
    uint256 _auctionId,
    uint256 amount,
    uint256 minOut
  ) external nonReentrant onlyActive {
    AuctionExits storage auctionExits = auctionEarlyExits[_auctionId];

    (, uint256 maltQuantity, uint256 newAmount) = earlyExitReturn(
      msg.sender,
      _auctionId,
      amount
    );

    require(maltQuantity > 0, "ExitEarly: Insufficient output");

    malt.mint(address(dexHandler), maltQuantity);
    // Early exits happen below peg in recovery mode
    // So risk of sandwich is very low
    uint256 amountOut = dexHandler.sellMalt(maltQuantity, 5000);

    require(amountOut >= minOut, "EarlyExit: Insufficient output");

    auctionExits.exitedEarly += newAmount;
    auctionExits.earlyExitReturn += amountOut;
    auctionExits.maltUsed += maltQuantity;
    auctionExits.accountExits[msg.sender].exitedEarly += newAmount;
    auctionExits.accountExits[msg.sender].earlyExitReturn += amountOut;
    auctionExits.accountExits[msg.sender].maltUsed += maltQuantity;

    auction.accountExit(msg.sender, _auctionId, newAmount);

    collateralToken.safeTransfer(msg.sender, amountOut);
    emit EarlyExit(msg.sender, newAmount, amountOut);
  }

  function earlyExitReturn(
    address account,
    uint256 _auctionId,
    uint256 amount
  )
    public
    view
    returns (
      uint256 exitAmount,
      uint256 maltValue,
      uint256 usedAmount
    )
  {
    // We don't need all the values
    (
      ,
      ,
      ,
      ,
      ,
      uint256 pegPrice,
      ,
      uint256 auctionEndTime,
      ,
      bool active
    ) = auction.getAuctionCore(_auctionId);

    // Cannot exit within 10% of the cooloffPeriod
    if (
      active ||
      block.timestamp < auctionEndTime + (cooloffPeriod * 10000) / 100000
    ) {
      return (0, 0, amount);
    }

    (uint256 maltQuantity, uint256 newAmount) = _getEarlyExitMaltQuantity(
      account,
      _auctionId,
      amount
    );

    if (maltQuantity == 0) {
      return (0, 0, newAmount);
    }

    // Reading direct from pool for this isn't bad as recovery
    // Mode avoids price being manipulated upwards
    (uint256 currentPrice, ) = dexHandler.maltMarketPrice();
    require(currentPrice != 0, "Price should be more than zero");

    uint256 fullReturn = (maltQuantity * currentPrice) / pegPrice;

    // setCooloffPeriod guards against cooloffPeriod ever being 0
    uint256 progressionBps = ((block.timestamp - auctionEndTime) * 10000) /
      cooloffPeriod;
    if (progressionBps > 10000) {
      progressionBps = 10000;
    }

    if (fullReturn > newAmount) {
      // Allow a % of profit to be realised
      // Add additional * 10,000 then / 10,000 to increase precision
      uint256 maxProfit = ((fullReturn - newAmount) *
        ((maxEarlyExitBps * 10000 * progressionBps) / 10000)) /
        10000 /
        10000;
      fullReturn = newAmount + maxProfit;
    }

    return (fullReturn, (fullReturn * pegPrice) / currentPrice, newAmount);
  }

  function accountEarlyExitReturns(address account)
    external
    view
    returns (uint256[] memory auctions, uint256[] memory earlyExitAmount)
  {
    auctions = auction.getAccountCommitmentAuctions(account);
    uint256 length = auctions.length;

    earlyExitAmount = new uint256[](length);

    for (uint256 i; i < length; ++i) {
      (uint256 commitment, uint256 redeemed, , uint256 exited) = auction
        .getAuctionParticipationForAccount(account, auctions[i]);
      uint256 amount = commitment - redeemed - exited;
      (uint256 exitAmount, , ) = earlyExitReturn(account, auctions[i], amount);
      earlyExitAmount[i] = exitAmount;
    }
  }

  function accountAuctionExits(address account, uint256 auctionId)
    external
    view
    returns (
      uint256 exitedEarly,
      uint256 earlyExitReturn,
      uint256 maltUsed
    )
  {
    EarlyExitData storage accountExits = auctionEarlyExits[auctionId]
      .accountExits[account];

    return (
      accountExits.exitedEarly,
      accountExits.earlyExitReturn,
      accountExits.maltUsed
    );
  }

  function globalAuctionExits(uint256 auctionId)
    external
    view
    returns (
      uint256 exitedEarly,
      uint256 earlyExitReturn,
      uint256 maltUsed
    )
  {
    AuctionExits storage auctionExits = auctionEarlyExits[auctionId];

    return (
      auctionExits.exitedEarly,
      auctionExits.earlyExitReturn,
      auctionExits.maltUsed
    );
  }

  /*
   * INTERNAL METHODS
   */
  function _calculateMaltRequiredForExit(
    uint256 _auctionId,
    uint256 amount,
    uint256 exitedEarly
  ) internal returns (uint256, uint256) {}

  function _getEarlyExitMaltQuantity(
    address account,
    uint256 _auctionId,
    uint256 amount
  ) internal view returns (uint256 maltQuantity, uint256 newAmount) {
    (
      uint256 userCommitment,
      uint256 userRedeemed,
      uint256 userMaltPurchased,
      uint256 earlyExited
    ) = auction.getAuctionParticipationForAccount(account, _auctionId);

    uint256 exitedEarly = auctionEarlyExits[_auctionId]
      .accountExits[account]
      .exitedEarly;

    // This should never overflow due to guards in redemption code
    uint256 userOutstanding = userCommitment - userRedeemed - exitedEarly;

    if (amount > userOutstanding) {
      amount = userOutstanding;
    }

    if (amount == 0) {
      return (0, 0);
    }

    newAmount = amount;

    maltQuantity = (userMaltPurchased * amount) / userCommitment;
  }

  /*
   * PRIVILEDGED METHODS
   */
  function setEarlyExitBps(uint256 _earlyExitBps)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(
      _earlyExitBps != 0 && _earlyExitBps <= 10000,
      "Must be between 0-100%"
    );
    maxEarlyExitBps = _earlyExitBps;
    emit SetEarlyExitBps(_earlyExitBps);
  }

  function setCooloffPeriod(uint256 _period)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_period != 0, "Cannot have 0 cool-off period");
    cooloffPeriod = _period;
    emit SetCooloffPeriod(_period);
  }

  function _accessControl()
    internal
    override(AuctionExtension, DexHandlerExtension)
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
