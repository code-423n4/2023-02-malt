// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/Math.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/LiquidityExtensionExtension.sol";
import "../StabilizedPoolExtensions/StabilizerNodeExtension.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../StabilizedPoolExtensions/DexHandlerExtension.sol";
import "../StabilizedPoolExtensions/ProfitDistributorExtension.sol";
import "../interfaces/IMaltDataLab.sol";
import "../interfaces/IDexHandler.sol";
import "../interfaces/ILiquidityExtension.sol";
import "../interfaces/IAuctionStartController.sol";

struct AccountCommitment {
  uint256 commitment;
  uint256 redeemed;
  uint256 maltPurchased;
  uint256 exited;
}

struct AuctionData {
  // The full amount of commitments required to return to peg
  uint256 fullRequirement;
  // total maximum desired commitments to this auction
  uint256 maxCommitments;
  // Quantity of sale currency committed to this auction
  uint256 commitments;
  // Quantity of commitments that have been exited early
  uint256 exited;
  // Malt purchased and burned using current commitments
  uint256 maltPurchased;
  // Desired starting price for the auction
  uint256 startingPrice;
  // Desired lowest price for the arbitrage token
  uint256 endingPrice;
  // Price of arbitrage tokens at conclusion of auction. This is either
  // when the duration elapses or the maxCommitments is reached
  uint256 finalPrice;
  // The peg price for the liquidity pool
  uint256 pegPrice;
  // Time when auction started
  uint256 startingTime;
  uint256 endingTime;
  // The reserve ratio at the start of the auction
  uint256 preAuctionReserveRatio;
  // The amount of arb tokens that have been executed and are now claimable
  uint256 claimableTokens;
  // The finally calculated realBurnBudget
  uint256 finalBurnBudget;
  // Is the auction currently accepting commitments?
  bool active;
  // Has this auction been finalized? Meaning any additional stabilizing
  // has been done
  bool finalized;
  // A map of all commitments to this auction by specific accounts
  mapping(address => AccountCommitment) accountCommitments;
}

/// @title Malt Arbitrage Auction
/// @author 0xScotch <scotch@malt.money>
/// @notice The under peg Malt mechanism of dutch arbitrage auctions is implemented here
contract Auction is
  StabilizedPoolUnit,
  LiquidityExtensionExtension,
  StabilizerNodeExtension,
  DataLabExtension,
  DexHandlerExtension,
  ProfitDistributorExtension
{
  using SafeERC20 for ERC20;

  bytes32 public immutable AUCTION_AMENDER_ROLE;
  bytes32 public immutable PROFIT_ALLOCATOR_ROLE;

  address public amender;

  uint256 public unclaimedArbTokens;
  uint256 public replenishingAuctionId;
  uint256 public currentAuctionId;
  uint256 public claimableArbitrageRewards;
  uint256 public nextCommitmentId;
  uint256 public auctionLength = 600; // 10 minutes
  uint256 public arbTokenReplenishSplitBps = 7000; // 70%
  uint256 public maxAuctionEndBps = 9000; // 90% of target price
  uint256 public auctionEndReserveBps = 9000; // 90% of collateral
  uint256 public priceLookback = 0;
  uint256 public reserveRatioLookback = 30; // 30 seconds
  uint256 public dustThreshold = 1e15;
  uint256 public earlyEndThreshold;
  uint256 public costBufferBps = 1000;
  uint256 private _replenishLimit = 10;

  address public auctionStartController;

  mapping(uint256 => AuctionData) internal idToAuction;
  mapping(address => uint256[]) internal accountCommitmentEpochs;

  event AuctionCommitment(
    uint256 commitmentId,
    uint256 auctionId,
    address indexed account,
    uint256 commitment,
    uint256 purchased
  );

  event ClaimArbTokens(
    uint256 auctionId,
    address indexed account,
    uint256 amountTokens
  );

  event AuctionEnded(
    uint256 id,
    uint256 commitments,
    uint256 startingPrice,
    uint256 finalPrice,
    uint256 maltPurchased
  );

  event AuctionStarted(
    uint256 id,
    uint256 maxCommitments,
    uint256 startingPrice,
    uint256 endingPrice,
    uint256 startingTime,
    uint256 endingTime
  );

  event ArbTokenAllocation(
    uint256 replenishingAuctionId,
    uint256 maxArbAllocation
  );

  event SetAuctionLength(uint256 length);
  event SetAuctionEndReserveBps(uint256 bps);
  event SetDustThreshold(uint256 threshold);
  event SetReserveRatioLookback(uint256 lookback);
  event SetPriceLookback(uint256 lookback);
  event SetMaxAuctionEnd(uint256 maxEnd);
  event SetTokenReplenishSplit(uint256 split);
  event SetAuctionStartController(address controller);
  event SetAuctionReplenishId(uint256 id);
  event SetEarlyEndThreshold(uint256 threshold);
  event SetCostBufferBps(uint256 costBuffer);

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    uint256 _auctionLength,
    uint256 _earlyEndThreshold
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    auctionLength = _auctionLength;
    earlyEndThreshold = _earlyEndThreshold;

    // keccak256("AUCTION_AMENDER_ROLE")
    AUCTION_AMENDER_ROLE = 0x7cfd4d3ca87651951a5df4ff76005c956036fd9aa4b22e6e574caaa56f487f68;
    // keccak256("PROFIT_ALLOCATOR_ROLE")
    PROFIT_ALLOCATOR_ROLE = 0x00ed6845b200b0f3e6539c45853016f38cb1b785c1d044aea74da930e58c7c4c;
  }

  function setupContracts(
    address _collateralToken,
    address _liquidityExtension,
    address _stabilizerNode,
    address _maltDataLab,
    address _dexHandler,
    address _amender,
    address _profitDistributor,
    address pool
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must be pool factory") {
    require(!contractActive, "Auction: Already setup");
    require(_collateralToken != address(0), "Auction: Col addr(0)");
    require(_liquidityExtension != address(0), "Auction: LE addr(0)");
    require(_stabilizerNode != address(0), "Auction: StabNode addr(0)");
    require(_maltDataLab != address(0), "Auction: DataLab addr(0)");
    require(_dexHandler != address(0), "Auction: DexHandler addr(0)");
    require(_amender != address(0), "Auction: Amender addr(0)");
    require(_profitDistributor != address(0), "Auction: ProfitDist addr(0)");

    contractActive = true;

    _roleSetup(AUCTION_AMENDER_ROLE, _amender);
    _roleSetup(PROFIT_ALLOCATOR_ROLE, _profitDistributor);
    _setupRole(STABILIZER_NODE_ROLE, _stabilizerNode);

    collateralToken = ERC20(_collateralToken);
    liquidityExtension = ILiquidityExtension(_liquidityExtension);
    stabilizerNode = IStabilizerNode(_stabilizerNode);
    maltDataLab = IMaltDataLab(_maltDataLab);
    dexHandler = IDexHandler(_dexHandler);
    amender = _amender;
    profitDistributor = IProfitDistributor(_profitDistributor);

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

  function _beforeSetProfitDistributor(address _profitDistributor)
    internal
    override
  {
    _transferRole(
      _profitDistributor,
      address(profitDistributor),
      PROFIT_ALLOCATOR_ROLE
    );
  }

  /*
   * PUBLIC METHODS
   */
  function purchaseArbitrageTokens(uint256 amount, uint256 minPurchased)
    external
    nonReentrant
    onlyActive
  {
    uint256 currentAuction = currentAuctionId;
    require(auctionActive(currentAuction), "No auction running");
    require(amount != 0, "purchaseArb: 0 amount");

    uint256 oldBalance = collateralToken.balanceOf(address(liquidityExtension));

    collateralToken.safeTransferFrom(
      msg.sender,
      address(liquidityExtension),
      amount
    );

    uint256 realAmount = collateralToken.balanceOf(
      address(liquidityExtension)
    ) - oldBalance;

    require(realAmount <= amount, "Invalid amount");

    uint256 realCommitment = _capCommitment(currentAuction, realAmount);
    require(realCommitment != 0, "ArbTokens: Real Commitment 0");

    uint256 purchased = liquidityExtension.purchaseAndBurn(realCommitment);
    require(purchased >= minPurchased, "ArbTokens: Insufficient output");

    AuctionData storage auction = idToAuction[currentAuction];

    require(
      auction.startingTime <= block.timestamp,
      "Auction hasn't started yet"
    );
    require(auction.endingTime > block.timestamp, "Auction is already over");
    require(auction.active == true, "Auction is not active");

    auction.commitments = auction.commitments + realCommitment;

    if (auction.accountCommitments[msg.sender].commitment == 0) {
      accountCommitmentEpochs[msg.sender].push(currentAuction);
    }
    auction.accountCommitments[msg.sender].commitment =
      auction.accountCommitments[msg.sender].commitment +
      realCommitment;
    auction.accountCommitments[msg.sender].maltPurchased =
      auction.accountCommitments[msg.sender].maltPurchased +
      purchased;
    auction.maltPurchased = auction.maltPurchased + purchased;

    emit AuctionCommitment(
      nextCommitmentId,
      currentAuction,
      msg.sender,
      realCommitment,
      purchased
    );

    nextCommitmentId = nextCommitmentId + 1;

    if (auction.commitments + auction.pegPrice >= auction.maxCommitments) {
      _endAuction(currentAuction);
    }
  }

  function claimArbitrage(uint256 _auctionId) external nonReentrant onlyActive {
    uint256 amountTokens = userClaimableArbTokens(msg.sender, _auctionId);

    require(amountTokens > 0, "No claimable Arb tokens");

    AuctionData storage auction = idToAuction[_auctionId];

    require(!auction.active, "Cannot claim tokens on an active auction");

    AccountCommitment storage commitment = auction.accountCommitments[
      msg.sender
    ];

    uint256 redemption = (amountTokens * auction.finalPrice) / auction.pegPrice;
    uint256 remaining = commitment.commitment -
      commitment.redeemed -
      commitment.exited;

    if (redemption > remaining) {
      redemption = remaining;
    }

    commitment.redeemed = commitment.redeemed + redemption;

    // Unclaimed represents total outstanding, but not necessarily
    // claimable yet.
    // claimableArbitrageRewards represents total amount that is now
    // available to be claimed
    if (amountTokens > unclaimedArbTokens) {
      unclaimedArbTokens = 0;
    } else {
      unclaimedArbTokens = unclaimedArbTokens - amountTokens;
    }

    if (amountTokens > claimableArbitrageRewards) {
      claimableArbitrageRewards = 0;
    } else {
      claimableArbitrageRewards = claimableArbitrageRewards - amountTokens;
    }

    uint256 totalBalance = collateralToken.balanceOf(address(this));
    if (amountTokens + dustThreshold >= totalBalance) {
      amountTokens = totalBalance;
    }

    collateralToken.safeTransfer(msg.sender, amountTokens);

    emit ClaimArbTokens(_auctionId, msg.sender, amountTokens);
  }

  function endAuctionEarly() external onlyActive {
    uint256 currentId = currentAuctionId;
    AuctionData storage auction = idToAuction[currentId];
    require(
      auction.active && block.timestamp >= auction.startingTime,
      "No auction running"
    );
    require(
      auction.commitments >= (auction.maxCommitments - earlyEndThreshold),
      "Too early to end"
    );

    _endAuction(currentId);
  }

  /*
   * PUBLIC VIEW FUNCTIONS
   */
  function isAuctionFinished(uint256 _id) public view returns (bool) {
    AuctionData storage auction = idToAuction[_id];

    return
      auction.endingTime > 0 &&
      (block.timestamp >= auction.endingTime ||
        auction.finalPrice > 0 ||
        auction.commitments + auction.pegPrice >= auction.maxCommitments);
  }

  function auctionActive(uint256 _id) public view returns (bool) {
    AuctionData storage auction = idToAuction[_id];

    return auction.active && block.timestamp >= auction.startingTime;
  }

  function isAuctionFinalized(uint256 _id) public view returns (bool) {
    AuctionData storage auction = idToAuction[_id];
    return auction.finalized;
  }

  function userClaimableArbTokens(address account, uint256 auctionId)
    public
    view
    returns (uint256)
  {
    AuctionData storage auction = idToAuction[auctionId];

    if (
      auction.claimableTokens == 0 ||
      auction.finalPrice == 0 ||
      auction.commitments == 0
    ) {
      return 0;
    }

    AccountCommitment storage commitment = auction.accountCommitments[account];

    uint256 totalTokens = (auction.commitments * auction.pegPrice) /
      auction.finalPrice;

    uint256 claimablePerc = (auction.claimableTokens * auction.pegPrice) /
      totalTokens;

    uint256 amountTokens = (commitment.commitment * auction.pegPrice) /
      auction.finalPrice;
    uint256 redeemedTokens = (commitment.redeemed * auction.pegPrice) /
      auction.finalPrice;
    uint256 exitedTokens = (commitment.exited * auction.pegPrice) /
      auction.finalPrice;

    uint256 amountOut = ((amountTokens * claimablePerc) / auction.pegPrice) -
      redeemedTokens -
      exitedTokens;

    // Avoid leaving dust behind
    if (amountOut < dustThreshold) {
      return 0;
    }

    return amountOut;
  }

  function balanceOfArbTokens(uint256 _auctionId, address account)
    public
    view
    returns (uint256)
  {
    AuctionData storage auction = idToAuction[_auctionId];

    AccountCommitment storage commitment = auction.accountCommitments[account];

    uint256 remaining = commitment.commitment -
      commitment.redeemed -
      commitment.exited;

    uint256 price = auction.finalPrice;

    if (auction.finalPrice == 0) {
      price = currentPrice(_auctionId);
    }

    return (remaining * auction.pegPrice) / price;
  }

  function averageMaltPrice(uint256 _id) external view returns (uint256) {
    AuctionData storage auction = idToAuction[_id];

    if (auction.maltPurchased == 0) {
      return 0;
    }

    return (auction.commitments * auction.pegPrice) / auction.maltPurchased;
  }

  function currentPrice(uint256 _id) public view returns (uint256) {
    AuctionData storage auction = idToAuction[_id];

    if (auction.startingTime == 0) {
      return maltDataLab.priceTarget();
    }

    uint256 secondsSinceStart = 0;

    if (block.timestamp > auction.startingTime) {
      secondsSinceStart = block.timestamp - auction.startingTime;
    }

    uint256 auctionDuration = auction.endingTime - auction.startingTime;

    if (secondsSinceStart >= auctionDuration) {
      return auction.endingPrice;
    }

    uint256 totalPriceDelta = auction.startingPrice - auction.endingPrice;

    uint256 currentPriceDelta = (totalPriceDelta * secondsSinceStart) /
      auctionDuration;

    return auction.startingPrice - currentPriceDelta;
  }

  function getAuctionCommitments(uint256 _id)
    public
    view
    returns (uint256 commitments, uint256 maxCommitments)
  {
    AuctionData storage auction = idToAuction[_id];

    return (auction.commitments, auction.maxCommitments);
  }

  function getAuctionPrices(uint256 _id)
    public
    view
    returns (
      uint256 startingPrice,
      uint256 endingPrice,
      uint256 finalPrice
    )
  {
    AuctionData storage auction = idToAuction[_id];

    return (auction.startingPrice, auction.endingPrice, auction.finalPrice);
  }

  function auctionExists(uint256 _id) public view returns (bool) {
    AuctionData storage auction = idToAuction[_id];

    return auction.startingTime > 0;
  }

  function getAccountCommitments(address account)
    external
    view
    returns (
      uint256[] memory auctions,
      uint256[] memory commitments,
      uint256[] memory awardedTokens,
      uint256[] memory redeemedTokens,
      uint256[] memory exitedTokens,
      uint256[] memory finalPrice,
      uint256[] memory claimable,
      bool[] memory finished
    )
  {
    uint256[] memory epochCommitments = accountCommitmentEpochs[account];

    auctions = new uint256[](epochCommitments.length);
    commitments = new uint256[](epochCommitments.length);
    awardedTokens = new uint256[](epochCommitments.length);
    redeemedTokens = new uint256[](epochCommitments.length);
    exitedTokens = new uint256[](epochCommitments.length);
    finalPrice = new uint256[](epochCommitments.length);
    claimable = new uint256[](epochCommitments.length);
    finished = new bool[](epochCommitments.length);

    for (uint256 i = 0; i < epochCommitments.length; ++i) {
      AuctionData storage auction = idToAuction[epochCommitments[i]];

      AccountCommitment storage commitment = auction.accountCommitments[
        account
      ];

      uint256 price = auction.finalPrice;

      if (auction.finalPrice == 0) {
        price = currentPrice(epochCommitments[i]);
      }

      auctions[i] = epochCommitments[i];
      commitments[i] = commitment.commitment;
      awardedTokens[i] = (commitment.commitment * auction.pegPrice) / price;
      redeemedTokens[i] = (commitment.redeemed * auction.pegPrice) / price;
      exitedTokens[i] = (commitment.exited * auction.pegPrice) / price;
      finalPrice[i] = price;
      claimable[i] = userClaimableArbTokens(account, epochCommitments[i]);
      finished[i] = isAuctionFinished(epochCommitments[i]);
    }
  }

  function getAccountCommitmentAuctions(address account)
    external
    view
    returns (uint256[] memory)
  {
    return accountCommitmentEpochs[account];
  }

  function getAuctionParticipationForAccount(address account, uint256 auctionId)
    external
    view
    returns (
      uint256 commitment,
      uint256 redeemed,
      uint256 maltPurchased,
      uint256 exited
    )
  {
    AccountCommitment storage _commitment = idToAuction[auctionId]
      .accountCommitments[account];

    return (
      _commitment.commitment,
      _commitment.redeemed,
      _commitment.maltPurchased,
      _commitment.exited
    );
  }

  function hasOngoingAuction() external view returns (bool) {
    AuctionData storage auction = idToAuction[currentAuctionId];

    return auction.startingTime > 0 && !auction.finalized;
  }

  function getActiveAuction()
    external
    view
    returns (
      uint256 auctionId,
      uint256 maxCommitments,
      uint256 commitments,
      uint256 maltPurchased,
      uint256 startingPrice,
      uint256 endingPrice,
      uint256 finalPrice,
      uint256 pegPrice,
      uint256 startingTime,
      uint256 endingTime,
      uint256 finalBurnBudget
    )
  {
    AuctionData storage auction = idToAuction[currentAuctionId];

    return (
      currentAuctionId,
      auction.maxCommitments,
      auction.commitments,
      auction.maltPurchased,
      auction.startingPrice,
      auction.endingPrice,
      auction.finalPrice,
      auction.pegPrice,
      auction.startingTime,
      auction.endingTime,
      auction.finalBurnBudget
    );
  }

  function getAuction(uint256 _id)
    public
    view
    returns (
      uint256 fullRequirement,
      uint256 maxCommitments,
      uint256 commitments,
      uint256 startingPrice,
      uint256 endingPrice,
      uint256 finalPrice,
      uint256 pegPrice,
      uint256 startingTime,
      uint256 endingTime,
      uint256 finalBurnBudget,
      uint256 exited
    )
  {
    AuctionData storage auction = idToAuction[_id];

    return (
      auction.fullRequirement,
      auction.maxCommitments,
      auction.commitments,
      auction.startingPrice,
      auction.endingPrice,
      auction.finalPrice,
      auction.pegPrice,
      auction.startingTime,
      auction.endingTime,
      auction.finalBurnBudget,
      auction.exited
    );
  }

  function getAuctionCore(uint256 _id)
    public
    view
    returns (
      uint256 auctionId,
      uint256 commitments,
      uint256 maltPurchased,
      uint256 startingPrice,
      uint256 finalPrice,
      uint256 pegPrice,
      uint256 startingTime,
      uint256 endingTime,
      uint256 preAuctionReserveRatio,
      bool active
    )
  {
    AuctionData storage auction = idToAuction[_id];

    return (
      _id,
      auction.commitments,
      auction.maltPurchased,
      auction.startingPrice,
      auction.finalPrice,
      auction.pegPrice,
      auction.startingTime,
      auction.endingTime,
      auction.preAuctionReserveRatio,
      auction.active
    );
  }

  /*
   * INTERNAL FUNCTIONS
   */
  function _triggerAuction(
    uint256 pegPrice,
    uint256 rRatio,
    uint256 purchaseAmount
  ) internal returns (bool) {
    if (auctionStartController != address(0)) {
      bool success = IAuctionStartController(auctionStartController)
        .checkForStart();
      if (!success) {
        return false;
      }
    }
    uint256 _auctionIndex = currentAuctionId;

    (uint256 startingPrice, uint256 endingPrice) = _calculateAuctionPricing(
      rRatio,
      purchaseAmount
    );

    AuctionData storage auction = idToAuction[_auctionIndex];

    uint256 decimals = collateralToken.decimals();
    uint256 maxCommitments = _calcRealMaxRaise(
      purchaseAmount,
      rRatio,
      decimals
    );

    if (maxCommitments == 0) {
      return false;
    }

    auction.fullRequirement = purchaseAmount; // fullRequirement
    auction.maxCommitments = maxCommitments;
    auction.startingPrice = startingPrice;
    auction.endingPrice = endingPrice;
    auction.pegPrice = pegPrice;
    auction.startingTime = block.timestamp; // startingTime
    auction.endingTime = block.timestamp + auctionLength; // endingTime
    auction.active = true; // active
    auction.preAuctionReserveRatio = rRatio; // preAuctionReserveRatio
    auction.finalized = false; // finalized

    require(
      auction.endingTime == uint256(uint64(auction.endingTime)),
      "ending not eq"
    );

    emit AuctionStarted(
      _auctionIndex,
      auction.maxCommitments,
      auction.startingPrice,
      auction.endingPrice,
      auction.startingTime,
      auction.endingTime
    );
    return true;
  }

  function _capCommitment(uint256 _id, uint256 _commitment)
    internal
    view
    returns (uint256 realCommitment)
  {
    AuctionData storage auction = idToAuction[_id];

    realCommitment = _commitment;

    if (auction.commitments + _commitment >= auction.maxCommitments) {
      realCommitment = auction.maxCommitments - auction.commitments;
    }
  }

  function _endAuction(uint256 _id) internal {
    AuctionData storage auction = idToAuction[_id];

    require(auction.active == true, "Auction is already over");

    auction.active = false;
    auction.finalPrice = currentPrice(_id);

    uint256 amountArbTokens = (auction.commitments * auction.pegPrice) /
      auction.finalPrice;
    unclaimedArbTokens = unclaimedArbTokens + amountArbTokens;

    emit AuctionEnded(
      _id,
      auction.commitments,
      auction.startingPrice,
      auction.finalPrice,
      auction.maltPurchased
    );
  }

  function _finalizeAuction(uint256 auctionId) internal {
    (
      uint256 avgMaltPrice,
      uint256 commitments,
      uint256 fullRequirement,
      uint256 maltPurchased,
      uint256 finalPrice,
      uint256 preAuctionReserveRatio
    ) = _setupAuctionFinalization(auctionId);

    if (commitments >= fullRequirement) {
      return;
    }

    uint256 priceTarget = maltDataLab.priceTarget();

    // priceTarget - preAuctionReserveRatio represents maximum deficit per token
    // priceTarget divided by the max deficit is equivalent to 1 over the max deficit given we are in uint decimal
    // (commitments * 1/maxDeficit) - commitments
    uint256 maxBurnSpend = (commitments * priceTarget) /
      (priceTarget - preAuctionReserveRatio) -
      commitments;

    uint256 totalTokens = (commitments * priceTarget) / finalPrice;

    uint256 premiumExcess = 0;

    // The assumption here is that each token will be worth 1 Malt when redeemed.
    // Therefore if totalTokens is greater than the malt purchased then there is a net supply growth
    // After the tokens are repaid. We want this process to be neutral to supply at the very worst.
    if (totalTokens > maltPurchased) {
      // This also assumes current purchase price of Malt is $1, which is higher than it will be in practice.
      // So the premium excess will actually ensure slight net negative supply growth.
      premiumExcess = totalTokens - maltPurchased;
    }

    uint256 realBurnBudget = maltDataLab.getRealBurnBudget(
      maxBurnSpend,
      premiumExcess
    );

    if (realBurnBudget > 0) {
      AuctionData storage auction = idToAuction[auctionId];

      auction.finalBurnBudget = realBurnBudget;
      liquidityExtension.allocateBurnBudget(realBurnBudget);
    }
  }

  function _setupAuctionFinalization(uint256 auctionId)
    internal
    returns (
      uint256 avgMaltPrice,
      uint256 commitments,
      uint256 fullRequirement,
      uint256 maltPurchased,
      uint256 finalPrice,
      uint256 preAuctionReserveRatio
    )
  {
    AuctionData storage auction = idToAuction[auctionId];
    require(auction.startingTime > 0, "No auction available for the given id");

    auction.finalized = true;

    if (auction.maltPurchased > 0) {
      avgMaltPrice =
        (auction.commitments * auction.pegPrice) /
        auction.maltPurchased;
    }

    return (
      avgMaltPrice,
      auction.commitments,
      auction.fullRequirement,
      auction.maltPurchased,
      auction.finalPrice,
      auction.preAuctionReserveRatio
    );
  }

  function _calcRealMaxRaise(
    uint256 purchaseAmount,
    uint256 rRatio,
    uint256 decimals
  ) internal pure returns (uint256) {
    uint256 unity = 10**decimals;
    uint256 realBurn = (purchaseAmount * Math.min(rRatio, unity)) / unity;

    if (purchaseAmount > realBurn) {
      return purchaseAmount - realBurn;
    }

    return 0;
  }

  function _calculateAuctionPricing(uint256 rRatio, uint256 maxCommitments)
    internal
    view
    returns (uint256 startingPrice, uint256 endingPrice)
  {
    uint256 priceTarget = maltDataLab.priceTarget();
    if (rRatio > priceTarget) {
      rRatio = priceTarget;
    }
    startingPrice = maltDataLab.maltPriceAverage(priceLookback);
    uint256 liquidityExtensionBalance = collateralToken.balanceOf(
      address(liquidityExtension)
    );

    (uint256 latestPrice, ) = maltDataLab.lastMaltPrice();
    uint256 expectedMaltCost = priceTarget;
    if (latestPrice < priceTarget) {
      expectedMaltCost =
        latestPrice +
        ((priceTarget - latestPrice) * (5000 + costBufferBps)) /
        10000;
    }

    // rRatio should never be large enough for this to overflow
    // uint256 absoluteBottom = rRatio * auctionEndReserveBps / 10000;

    // Absolute bottom is the lowest price
    uint256 decimals = collateralToken.decimals();
    uint256 unity = 10**decimals;
    uint256 absoluteBottom = (maxCommitments * unity) /
      (liquidityExtensionBalance +
        ((maxCommitments * unity) / expectedMaltCost));

    uint256 idealBottom = 1; // 1wei just to avoid any issues with it being 0

    if (expectedMaltCost > rRatio) {
      idealBottom = expectedMaltCost - rRatio;
    }

    // price should never go below absoluteBottom
    if (idealBottom < absoluteBottom) {
      idealBottom = absoluteBottom;
    }

    // price should never start above the peg price
    if (startingPrice > priceTarget) {
      startingPrice = priceTarget;
    }

    if (idealBottom < startingPrice) {
      endingPrice = idealBottom;
    } else if (absoluteBottom < startingPrice) {
      endingPrice = absoluteBottom;
    } else {
      // There are no bottom prices that work with
      // the startingPrice so set start and end to
      // the absoluteBottom
      startingPrice = absoluteBottom;
      endingPrice = absoluteBottom;
    }

    // priceTarget should never be large enough to overflow here
    uint256 maxPrice = (priceTarget * maxAuctionEndBps) / 10000;

    if (endingPrice > maxPrice && maxPrice > absoluteBottom) {
      endingPrice = maxPrice;
    }
  }

  function _checkAuctionFinalization() internal {
    uint256 currentAuction = currentAuctionId;

    if (isAuctionFinished(currentAuction)) {
      if (auctionActive(currentAuction)) {
        _endAuction(currentAuction);
      }

      if (!isAuctionFinalized(currentAuction)) {
        _finalizeAuction(currentAuction);
      }
      currentAuctionId = currentAuction + 1;
    }
  }

  /*
   * PRIVILEDGED FUNCTIONS
   */
  function checkAuctionFinalization()
    external
    onlyRoleMalt(STABILIZER_NODE_ROLE, "Must be stabilizer node")
    onlyActive
  {
    _checkAuctionFinalization();
  }

  function accountExit(
    address account,
    uint256 auctionId,
    uint256 amount
  )
    external
    onlyRoleMalt(AUCTION_AMENDER_ROLE, "Only auction amender")
    onlyActive
  {
    AuctionData storage auction = idToAuction[auctionId];
    require(
      auction.accountCommitments[account].commitment >= amount,
      "amend: amount underflows"
    );

    if (auction.finalPrice == 0) {
      return;
    }

    auction.exited += amount;
    auction.accountCommitments[account].exited += amount;

    uint256 amountArbTokens = (amount * auction.pegPrice) / auction.finalPrice;

    if (amountArbTokens > unclaimedArbTokens) {
      unclaimedArbTokens = 0;
    } else {
      unclaimedArbTokens = unclaimedArbTokens - amountArbTokens;
    }
  }

  function allocateArbRewards(uint256 rewarded)
    external
    onlyRoleMalt(PROFIT_ALLOCATOR_ROLE, "Must be profit allocator node")
    onlyActive
    returns (uint256)
  {
    AuctionData storage auction;
    uint256 replenishingId = replenishingAuctionId; // gas
    uint256 absorbedCapital;
    uint256 count = 1;
    uint256 maxArbAllocation = (rewarded * arbTokenReplenishSplitBps) / 10000;

    // Limit iterations to avoid unbounded loops
    while (count < _replenishLimit) {
      auction = idToAuction[replenishingId];

      if (
        auction.finalPrice == 0 ||
        auction.startingTime == 0 ||
        !auction.finalized
      ) {
        // if finalPrice or startingTime are not set then this auction has not happened yet
        // So we are at the end of the journey
        break;
      }

      if (auction.commitments > 0) {
        uint256 totalTokens = (auction.commitments * auction.pegPrice) /
          auction.finalPrice;

        if (auction.claimableTokens < totalTokens) {
          uint256 requirement = totalTokens - auction.claimableTokens;

          uint256 usable = maxArbAllocation - absorbedCapital;

          if (absorbedCapital + requirement < maxArbAllocation) {
            usable = requirement;
          }

          auction.claimableTokens = auction.claimableTokens + usable;
          rewarded = rewarded - usable;
          claimableArbitrageRewards = claimableArbitrageRewards + usable;

          absorbedCapital += usable;

          emit ArbTokenAllocation(replenishingId, usable);

          if (auction.claimableTokens < totalTokens) {
            break;
          }
        }
      }

      replenishingId += 1;
      count += 1;
    }

    replenishingAuctionId = replenishingId;

    if (absorbedCapital != 0) {
      collateralToken.safeTransferFrom(
        address(profitDistributor),
        address(this),
        absorbedCapital
      );
    }

    return rewarded;
  }

  function triggerAuction(uint256 pegPrice, uint256 purchaseAmount)
    external
    onlyRoleMalt(STABILIZER_NODE_ROLE, "Must be stabilizer node")
    onlyActive
    returns (bool)
  {
    if (purchaseAmount == 0 || auctionExists(currentAuctionId)) {
      return false;
    }

    // Data is consistent here as this method as the stabilizer
    // calls maltDataLab.trackPool at the start of stabilize
    (uint256 rRatio, ) = liquidityExtension.reserveRatioAverage(
      reserveRatioLookback
    );

    return _triggerAuction(pegPrice, rRatio, purchaseAmount);
  }

  function setAuctionLength(uint256 _length)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_length > 0, "Length must be larger than 0");
    auctionLength = _length;
    emit SetAuctionLength(_length);
  }

  function setAuctionReplenishId(uint256 _id)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    replenishingAuctionId = _id;
    emit SetAuctionReplenishId(_id);
  }

  function setAuctionAmender(address _amender)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater privilege")
  {
    require(_amender != address(0), "Cannot set 0 address");
    _transferRole(_amender, amender, AUCTION_AMENDER_ROLE);
    amender = _amender;
  }

  function setAuctionStartController(address _controller)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    // This is allowed to be set to address(0) as its checked before calling methods on it
    auctionStartController = _controller;
    emit SetAuctionStartController(_controller);
  }

  function setTokenReplenishSplit(uint256 _split)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_split != 0 && _split <= 10000, "Must be between 0-100%");
    arbTokenReplenishSplitBps = _split;
    emit SetTokenReplenishSplit(_split);
  }

  function setMaxAuctionEnd(uint256 _maxEnd)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_maxEnd != 0 && _maxEnd <= 10000, "Must be between 0-100%");
    maxAuctionEndBps = _maxEnd;
    emit SetMaxAuctionEnd(_maxEnd);
  }

  function setPriceLookback(uint256 _lookback)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_lookback > 0, "Must be above 0");
    priceLookback = _lookback;
    emit SetPriceLookback(_lookback);
  }

  function setReserveRatioLookback(uint256 _lookback)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_lookback > 0, "Must be above 0");
    reserveRatioLookback = _lookback;
    emit SetReserveRatioLookback(_lookback);
  }

  function setAuctionEndReserveBps(uint256 _bps)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_bps != 0 && _bps < 10000, "Must be between 0-100%");
    auctionEndReserveBps = _bps;
    emit SetAuctionEndReserveBps(_bps);
  }

  function setDustThreshold(uint256 _threshold)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_threshold > 0, "Must be between greater than 0");
    dustThreshold = _threshold;
    emit SetDustThreshold(_threshold);
  }

  function setEarlyEndThreshold(uint256 _threshold)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_threshold > 0, "Must be between greater than 0");
    earlyEndThreshold = _threshold;
    emit SetEarlyEndThreshold(_threshold);
  }

  function setCostBufferBps(uint256 _costBuffer)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_costBuffer != 0 && _costBuffer <= 5000, "Must be > 0 && <= 5000");
    costBufferBps = _costBuffer;
    emit SetCostBufferBps(_costBuffer);
  }

  function adminEndAuction()
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    uint256 currentId = currentAuctionId;
    require(auctionActive(currentId), "No auction running");
    _endAuction(currentId);
  }

  function setReplenishLimit(uint256 _limit)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privilege")
  {
    require(_limit != 0, "Not 0");
    _replenishLimit = _limit;
  }

  function _accessControl()
    internal
    override(
      LiquidityExtensionExtension,
      StabilizerNodeExtension,
      DataLabExtension,
      DexHandlerExtension,
      ProfitDistributorExtension
    )
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
