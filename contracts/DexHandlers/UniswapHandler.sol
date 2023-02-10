// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../libraries/uniswap/IUniswapV2Router02.sol";
import "../libraries/uniswap/Babylonian.sol";
import "../libraries/uniswap/FullMath.sol";
import "../libraries/SafeBurnMintableERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../libraries/UniswapV2Library.sol";
import "../interfaces/IDexHandler.sol";
import "../interfaces/IMaltDataLab.sol";
import "../libraries/uniswap/IUniswapV2Pair.sol";

/// @title Uniswap Interaction Handler
/// @author 0xScotch <scotch@malt.money>
/// @notice A simple contract to make interacting with UniswapV2 pools easier.
/// @notice The buyMalt method is locked down to avoid circumventing recovery mode
/// @dev Makes use of UniswapV2Router02. Would be more efficient to go direct
contract UniswapHandler is StabilizedPoolUnit, IDexHandler, DataLabExtension {
  using SafeERC20 for ERC20;
  using SafeBurnMintableERC20 for IBurnMintableERC20;

  bytes32 public immutable BUYER_ROLE;
  bytes32 public immutable SELLER_ROLE;
  bytes32 public immutable LIQUIDITY_ADDER_ROLE;
  bytes32 public immutable LIQUIDITY_REMOVER_ROLE;

  IUniswapV2Router02 public router;

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    address _router
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    require(_router != address(0), "DexHandler: Router addr(0)");

    BUYER_ROLE = 0xf8cd32ed93fc2f9fc78152a14807c9609af3d99c5fe4dc6b106a801aaddfe90e;
    SELLER_ROLE = 0x43f25613eb2f15fb17222a5d424ca2655743e71265d98e4b93c05e5fb589ecde;
    LIQUIDITY_ADDER_ROLE = 0x03945f6c3051ab5ab2572e79ed50d335b86d27b15a2bde4e36c0cd1cd4e01197;
    LIQUIDITY_REMOVER_ROLE = 0xd47674765c67c9966091faf903d963f52df2a50d25ad1c519d46975de025d006;
    _setRoleAdmin(
      0xf8cd32ed93fc2f9fc78152a14807c9609af3d99c5fe4dc6b106a801aaddfe90e,
      0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775
    );
    _setRoleAdmin(
      0x43f25613eb2f15fb17222a5d424ca2655743e71265d98e4b93c05e5fb589ecde,
      0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775
    );
    _setRoleAdmin(
      0x03945f6c3051ab5ab2572e79ed50d335b86d27b15a2bde4e36c0cd1cd4e01197,
      0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775
    );
    _setRoleAdmin(
      0xd47674765c67c9966091faf903d963f52df2a50d25ad1c519d46975de025d006,
      0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775
    );

    router = IUniswapV2Router02(_router);
  }

  function setupContracts(
    address _malt,
    address _collateralToken,
    address _stakeToken,
    address _maltDataLab,
    address[] memory initialBuyers,
    address[] memory initialSellers,
    address[] memory initialLiquidityAdders,
    address[] memory initialLiquidityRemovers
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must be pool factory") {
    require(address(malt) == address(0), "UniswapHandler: Already setup");
    require(_malt != address(0), "UniswapHandler: Malt addr(0)");
    require(_collateralToken != address(0), "UniswapHandler: Col addr(0)");
    require(_stakeToken != address(0), "UniswapHandler: LP Token addr(0)");
    require(_maltDataLab != address(0), "UniswapHandler: MaltDataLab addr(0)");

    malt = IBurnMintableERC20(_malt);
    collateralToken = ERC20(_collateralToken);
    stakeToken = IUniswapV2Pair(_stakeToken);
    maltDataLab = IMaltDataLab(_maltDataLab);

    for (uint256 i; i < initialBuyers.length; ++i) {
      _grantRole(BUYER_ROLE, initialBuyers[i]);
    }
    for (uint256 i; i < initialSellers.length; ++i) {
      _grantRole(SELLER_ROLE, initialSellers[i]);
    }
    for (uint256 i; i < initialLiquidityAdders.length; ++i) {
      _grantRole(LIQUIDITY_ADDER_ROLE, initialLiquidityAdders[i]);
    }
    for (uint256 i; i < initialLiquidityRemovers.length; ++i) {
      _grantRole(LIQUIDITY_REMOVER_ROLE, initialLiquidityRemovers[i]);
    }

    (, address updater, ) = poolFactory.getPool(_stakeToken);
    _setPoolUpdater(updater);
  }

  /*
   * PUBLIC VIEW FUNCTIONS
   */
  function calculateMintingTradeSize(uint256 priceTarget)
    external
    view
    returns (uint256)
  {
    return
      _calculateTradeSize(address(malt), address(collateralToken), priceTarget);
  }

  function calculateBurningTradeSize(uint256 priceTarget)
    external
    view
    returns (uint256)
  {
    uint256 unity = 10**collateralToken.decimals();
    return
      _calculateTradeSize(
        address(collateralToken),
        address(malt),
        (unity * unity) / priceTarget
      );
  }

  function reserves()
    public
    view
    returns (uint256 maltSupply, uint256 rewardSupply)
  {
    (uint256 reserve0, uint256 reserve1, ) = stakeToken.getReserves();
    (maltSupply, rewardSupply) = address(malt) < address(collateralToken)
      ? (reserve0, reserve1)
      : (reserve1, reserve0);
  }

  function maltMarketPrice()
    public
    view
    returns (uint256 price, uint256 decimals)
  {
    (uint256 reserve0, uint256 reserve1, ) = stakeToken.getReserves();
    (uint256 maltReserves, uint256 rewardReserves) = address(malt) <
      address(collateralToken)
      ? (reserve0, reserve1)
      : (reserve1, reserve0);

    if (maltReserves == 0 || rewardReserves == 0) {
      price = 0;
      decimals = 18;
      return (price, decimals);
    }

    maltReserves = maltDataLab.maltToRewardDecimals(maltReserves);

    decimals = collateralToken.decimals();
    price = (rewardReserves * (10**decimals)) / maltReserves;
  }

  function getOptimalLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidityB
  ) external view returns (uint256 liquidityA) {
    (uint256 reserve0, uint256 reserve1, ) = stakeToken.getReserves();
    (uint256 reservesA, uint256 reservesB) = tokenA < tokenB
      ? (reserve0, reserve1)
      : (reserve1, reserve0);

    liquidityA = UniswapV2Library.quote(liquidityB, reservesB, reservesA);
  }

  /*
   * MUTATION FUNCTIONS
   */
  function buyMalt(uint256 amount, uint256 slippageBps)
    external
    onlyRoleMalt(BUYER_ROLE, "Must have buyer privs")
    returns (uint256 purchased)
  {
    require(
      amount <= collateralToken.balanceOf(address(this)),
      "buy: insufficient"
    );

    if (amount == 0) {
      return 0;
    }

    // Just make sure starting from 0
    collateralToken.safeApprove(address(router), 0);
    collateralToken.safeApprove(address(router), amount);

    address[] memory path = new address[](2);
    path[0] = address(collateralToken);
    path[1] = address(malt);

    uint256 maltPrice = maltDataLab.maltPriceAverage(0);

    uint256 initialBalance = malt.balanceOf(address(this));

    router.swapExactTokensForTokens(
      amount,
      (amount * (10**collateralToken.decimals()) * (10000 - slippageBps)) /
        maltPrice /
        10000, // amountOutMin
      path,
      address(this),
      block.timestamp
    );

    // Reset approval
    collateralToken.safeApprove(address(router), 0);

    purchased = malt.balanceOf(address(this)) - initialBalance;
    malt.safeTransfer(msg.sender, purchased);
  }

  function sellMalt(uint256 amount, uint256 slippageBps)
    external
    onlyRoleMalt(SELLER_ROLE, "Must have seller privs")
    returns (uint256 rewards)
  {
    require(amount <= malt.balanceOf(address(this)), "sell: insufficient");

    if (amount == 0) {
      return 0;
    }

    // Just make sure starting from 0
    malt.safeApprove(address(router), 0);
    malt.safeApprove(address(router), amount);

    address[] memory path = new address[](2);
    path[0] = address(malt);
    path[1] = address(collateralToken);

    uint256 maltPrice = maltDataLab.maltPriceAverage(0);
    uint256 initialBalance = collateralToken.balanceOf(address(this));

    router.swapExactTokensForTokens(
      amount,
      (amount * maltPrice * (10000 - slippageBps)) /
        (10**collateralToken.decimals()) /
        10000, // amountOutMin
      path,
      address(this),
      block.timestamp
    );

    // Reset approval
    malt.safeApprove(address(router), 0);

    rewards = collateralToken.balanceOf(address(this)) - initialBalance;
    collateralToken.safeTransfer(msg.sender, rewards);
  }

  function addLiquidity(
    uint256 maltBalance,
    uint256 rewardBalance,
    uint256 slippageBps
  )
    external
    onlyRoleMalt(LIQUIDITY_ADDER_ROLE, "Must have liq add privs")
    returns (
      uint256 maltUsed,
      uint256 rewardUsed,
      uint256 liquidityCreated
    )
  {
    // Thid method assumes the caller does the required checks on token ratios etc
    uint256 initialMalt = malt.balanceOf(address(this));
    uint256 initialReward = collateralToken.balanceOf(address(this));

    require(maltBalance <= initialMalt, "Add liquidity: malt");
    require(rewardBalance <= initialReward, "Add liquidity: reward");

    if (maltBalance == 0 || rewardBalance == 0) {
      return (0, 0, 0);
    }

    (maltUsed, rewardUsed, liquidityCreated) = _executeAddLiquidity(
      maltBalance,
      rewardBalance,
      slippageBps
    );

    if (maltUsed < initialMalt) {
      malt.safeTransfer(msg.sender, initialMalt - maltUsed);
    }

    if (rewardUsed < initialReward) {
      collateralToken.safeTransfer(msg.sender, initialReward - rewardUsed);
    }
  }

  function removeLiquidity(uint256 liquidityBalance, uint256 slippageBps)
    external
    onlyRoleMalt(LIQUIDITY_REMOVER_ROLE, "Must have liq remove privs")
    returns (uint256 amountMalt, uint256 amountReward)
  {
    require(
      liquidityBalance <= stakeToken.balanceOf(address(this)),
      "remove: Insufficient"
    );

    if (liquidityBalance == 0) {
      return (0, 0);
    }

    (amountMalt, amountReward) = _executeRemoveLiquidity(
      liquidityBalance,
      slippageBps
    );

    if (amountMalt == 0 || amountReward == 0) {
      liquidityBalance = stakeToken.balanceOf(address(this));
      ERC20(address(stakeToken)).safeTransfer(msg.sender, liquidityBalance);
      return (amountMalt, amountReward);
    }
  }

  /*
   * INTERNAL METHODS
   */
  function _executeAddLiquidity(
    uint256 maltBalance,
    uint256 rewardBalance,
    uint256 slippageBps
  )
    internal
    returns (
      uint256 maltUsed,
      uint256 rewardUsed,
      uint256 liquidityCreated
    )
  {
    // Make sure starting from 0
    collateralToken.safeApprove(address(router), 0);
    malt.safeApprove(address(router), 0);

    collateralToken.safeApprove(address(router), rewardBalance);
    malt.safeApprove(address(router), maltBalance);

    (maltUsed, rewardUsed, liquidityCreated) = router.addLiquidity(
      address(malt),
      address(collateralToken),
      maltBalance,
      rewardBalance,
      (maltBalance * (10000 - slippageBps)) / 10000,
      (rewardBalance * (10000 - slippageBps)) / 10000,
      msg.sender, // transfer LP tokens to sender
      block.timestamp
    );

    // Reset approval
    collateralToken.safeApprove(address(router), 0);
    malt.safeApprove(address(router), 0);
  }

  function _executeRemoveLiquidity(
    uint256 liquidityBalance,
    uint256 slippageBps
  ) internal returns (uint256 amountMalt, uint256 amountReward) {
    uint256 totalLPSupply = stakeToken.totalSupply();

    // Make sure starting from 0
    ERC20(address(stakeToken)).safeApprove(address(router), 0);
    ERC20(address(stakeToken)).safeApprove(address(router), liquidityBalance);

    (uint256 maltReserves, uint256 collateralReserves) = maltDataLab
      .poolReservesAverage(0);

    uint256 maltValue = (maltReserves * liquidityBalance) / totalLPSupply;
    uint256 collateralValue = (collateralReserves * liquidityBalance) /
      totalLPSupply;

    (amountMalt, amountReward) = router.removeLiquidity(
      address(malt),
      address(collateralToken),
      liquidityBalance,
      (maltValue * (10000 - slippageBps)) / 10000,
      (collateralValue * (10000 - slippageBps)) / 10000,
      address(this),
      block.timestamp
    );

    // Reset approval
    ERC20(address(stakeToken)).safeApprove(address(router), 0);

    malt.safeTransfer(msg.sender, amountMalt);
    collateralToken.safeTransfer(msg.sender, amountReward);
  }

  /*
   * PRIVATE METHODS
   */
  function _calculateTradeSize(
    address sellToken,
    address buyToken,
    uint256 priceTarget
  ) private view returns (uint256) {
    (uint256 sellReserves, uint256 invariant) = _getTradePoolData(
      sellToken,
      buyToken
    );

    uint256 buyBase = 10**uint256(ERC20(buyToken).decimals());

    uint256 leftSide = Babylonian.sqrt(
      FullMath.mulDiv(invariant * 1000, buyBase, priceTarget * 997)
    );

    uint256 rightSide = (sellReserves * 1000) / 997;

    if (leftSide < rightSide) return 0;

    return leftSide - rightSide;
  }

  function _getTradePoolData(address sellToken, address buyToken)
    private
    view
    returns (uint256 sellReserves, uint256 invariant)
  {
    (uint256 reserve0, uint256 reserve1, ) = stakeToken.getReserves();
    sellReserves = sellToken < buyToken ? reserve0 : reserve1;

    invariant = reserve1 * reserve0;
  }

  function addBuyer(address _buyer)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must be pool updater")
  {
    require(_buyer != address(0), "No addr(0)");
    _grantRole(BUYER_ROLE, _buyer);
  }

  function removeBuyer(address _buyer)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must be pool updater")
  {
    _revokeRole(BUYER_ROLE, _buyer);
  }

  function addSeller(address _seller)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must be pool updater")
  {
    require(_seller != address(0), "No addr(0)");
    _grantRole(SELLER_ROLE, _seller);
  }

  function removeSeller(address _seller)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must be pool updater")
  {
    _revokeRole(SELLER_ROLE, _seller);
  }

  function addLiquidityAdder(address _adder)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must be pool updater")
  {
    require(_adder != address(0), "No addr(0)");
    _grantRole(LIQUIDITY_ADDER_ROLE, _adder);
  }

  function removeLiquidityAdder(address _adder)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must be pool updater")
  {
    _revokeRole(LIQUIDITY_ADDER_ROLE, _adder);
  }

  function addLiquidityRemover(address _remover)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must be pool updater")
  {
    require(_remover != address(0), "No addr(0)");
    _grantRole(LIQUIDITY_REMOVER_ROLE, _remover);
  }

  function removeLiquidityRemover(address _remover)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must be pool updater")
  {
    _revokeRole(LIQUIDITY_REMOVER_ROLE, _remover);
  }

  function _accessControl() internal override(DataLabExtension) {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
