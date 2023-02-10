// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/AuctionExtension.sol";
import "../interfaces/IAuction.sol";

/// @title Auction Participant
/// @author 0xScotch <scotch@malt.money>
/// @notice Will generally be inherited to give another contract the ability to use its capital to buy arbitrage tokens
abstract contract AuctionParticipant is StabilizedPoolUnit, AuctionExtension {
  using SafeERC20 for ERC20;

  bytes32 public immutable PURCHASE_TRIGGER_ROLE;

  uint256 public replenishingIndex;
  uint256[] public auctionIds;
  mapping(uint256 => uint256) public idIndex;
  uint256 public claimableRewards;

  event SetReplenishingIndex(uint256 index);

  constructor(
    address timelock,
    address initialAdmin,
    address poolFactory,
    address purchaseExecutor
  ) StabilizedPoolUnit(timelock, initialAdmin, poolFactory) {
    PURCHASE_TRIGGER_ROLE = 0xba1d6c105756f1871c32a2336058dfcdec2b9a50c167d72adb7a3048e6502a75;
    // setup PURCHASE_TRIGGER_ROLE
    _roleSetup(
      0xba1d6c105756f1871c32a2336058dfcdec2b9a50c167d72adb7a3048e6502a75,
      purchaseExecutor
    );
  }

  function setupContracts(
    address _collateralToken,
    address _auction,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must be pool factory") {
    require(!contractActive, "Participant: Already setup");
    require(_collateralToken != address(0), "Participant: RewardToken addr(0)");
    require(_auction != address(0), "Participant: Auction addr(0)");

    contractActive = true;

    collateralToken = ERC20(_collateralToken);
    auction = IAuction(_auction);

    (, address updater, ) = poolFactory.getPool(pool);
    _setPoolUpdater(updater);
  }

  function purchaseArbitrageTokens(uint256 maxAmount)
    external
    onlyRoleMalt(
      PURCHASE_TRIGGER_ROLE,
      "Must have implied collateral service privs"
    )
    nonReentrant
    onlyActive
    returns (uint256 remaining)
  {
    // Just to make sure we are starting from 0
    collateralToken.safeApprove(address(auction), 0);

    uint256 balance = usableBalance();

    if (balance == 0) {
      return maxAmount;
    }

    if (maxAmount < balance) {
      balance = maxAmount;
    }

    uint256 currentAuction = auction.currentAuctionId();

    if (!auction.auctionActive(currentAuction)) {
      return maxAmount;
    }

    // First time participating in this auction
    if (idIndex[currentAuction] == 0) {
      auctionIds.push(currentAuction);
      idIndex[currentAuction] = auctionIds.length;
    }

    collateralToken.safeApprove(address(auction), balance);
    auction.purchaseArbitrageTokens(balance, 0); // 0 min due to blocking buys

    // Reset approval
    collateralToken.safeApprove(address(auction), 0);

    return maxAmount - balance;
  }

  function claim() external nonReentrant onlyActive {
    uint256 length = auctionIds.length;
    if (length == 0 || replenishingIndex >= length) {
      return;
    }

    uint256 currentIndex = replenishingIndex;
    uint256 auctionId = auctionIds[currentIndex];
    uint256 auctionReplenishing = auction.replenishingAuctionId();

    if (auctionId > auctionReplenishing) {
      // Not yet replenishing this auction
      return;
    }

    uint256 claimableTokens = auction.userClaimableArbTokens(
      address(this),
      auctionId
    );

    if (claimableTokens == 0 && auctionReplenishing > auctionId) {
      // in this case, we will never receive any more tokens from this auction
      currentIndex += 1;
      auctionId = auctionIds[currentIndex];
      claimableTokens = auction.userClaimableArbTokens(
        address(this),
        auctionId
      );
    }

    if (claimableTokens == 0) {
      // Nothing to claim yet
      replenishingIndex = currentIndex;
      return;
    }

    uint256 balance = collateralToken.balanceOf(address(this));

    auction.claimArbitrage(auctionId);

    uint256 finalBalance = collateralToken.balanceOf(address(this));
    uint256 rewardedAmount = finalBalance - balance;

    claimableRewards = claimableRewards + rewardedAmount;

    if (
      auction.replenishingAuctionId() > auctionId &&
      auction.userClaimableArbTokens(address(this), auctionId) == 0
    ) {
      // Don't increment replenishingIndex if replenishingAuctionId == auctionId as
      // claimable could be 0 due to the debt not being 100% replenished.
      currentIndex += 1;
    }

    replenishingIndex = currentIndex;

    _handleRewardDistribution(rewardedAmount);
  }

  function outstandingArbTokens() public view returns (uint256 outstanding) {
    outstanding = 0;

    uint256 length = auctionIds.length;

    for (uint256 i = replenishingIndex; i < length; i = i + 1) {
      outstanding =
        outstanding +
        auction.balanceOfArbTokens(auctionIds[i], address(this));
    }

    return outstanding;
  }

  function getAllAuctionIds() public view returns (uint256[] memory) {
    return auctionIds;
  }

  function usableBalance() public view virtual returns (uint256) {
    return collateralToken.balanceOf(address(this));
  }

  function _handleRewardDistribution(uint256 rewarded) internal virtual {
    // Do nothing
    return;
  }

  function setReplenishingIndex(uint256 _index)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    replenishingIndex = _index;
    emit SetReplenishingIndex(_index);
  }

  function _accessControl() internal override(AuctionExtension) {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
