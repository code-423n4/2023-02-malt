// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../StabilizedPoolExtensions/SwingTraderManagerExtension.sol";
import "../StabilizedPoolExtensions/LiquidityExtensionExtension.sol";
import "../StabilizedPoolExtensions/RewardOverflowExtension.sol";
import "../StabilizedPoolExtensions/AuctionExtension.sol";
import "../StabilizedPoolExtensions/GlobalICExtension.sol";
import "../StabilizedPoolExtensions/StabilizerNodeExtension.sol";
import "../interfaces/IAuction.sol";
import "../interfaces/IOverflow.sol";
import "../interfaces/IBurnMintableERC20.sol";
import "../interfaces/ISwingTrader.sol";
import "../interfaces/ILiquidityExtension.sol";
import "../interfaces/IMaltDataLab.sol";
import "../interfaces/IStabilizerNode.sol";
import "../interfaces/IGlobalImpliedCollateralService.sol";
import "../libraries/uniswap/IUniswapV2Pair.sol";
import "./PoolCollateral.sol";

import "forge-std/Script.sol";

/// @title Implied Collateral Service
/// @author 0xScotch <scotch@malt.money>
/// @notice A contract that provides an abstraction above individual implied collateral sources
contract ImpliedCollateralService is
  StabilizedPoolUnit,
  DataLabExtension,
  SwingTraderManagerExtension,
  LiquidityExtensionExtension,
  RewardOverflowExtension,
  AuctionExtension,
  GlobalICExtension,
  StabilizerNodeExtension
{
  using SafeERC20 for ERC20;

  constructor(
    address timelock,
    address repository,
    address poolFactory
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {}

  function setupContracts(
    address _collateralToken,
    address _malt,
    address _stakeToken,
    address _auction,
    address _rewardOverflow,
    address _swingTraderManager,
    address _liquidityExtension,
    address _maltDataLab,
    address _stabilizerNode,
    address _globalIC
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role") {
    require(!contractActive, "ImpCol: Already setup");
    require(_auction != address(0), "ImpCol: Auction addr(0)");
    require(_rewardOverflow != address(0), "ImpCol: Overflow addr(0)");
    require(_swingTraderManager != address(0), "ImpCol: Swing addr(0)");
    require(_liquidityExtension != address(0), "ImpCol: LE addr(0)");
    require(_maltDataLab != address(0), "ImpCol: DataLab addr(0)");
    require(_stabilizerNode != address(0), "ImpCol: StablizerNode addr(0)");
    require(_globalIC != address(0), "ImpCol: GlobalIC addr(0)");
    require(_collateralToken != address(0), "ImpCol: ColToken addr(0)");
    require(_malt != address(0), "ImpCol: Malt addr(0)");
    require(_stakeToken != address(0), "ImpCol: Stake Token addr(0)");

    contractActive = true;

    auction = IAuction(_auction);
    overflowPool = IOverflow(_rewardOverflow);
    swingTraderManager = ISwingTrader(_swingTraderManager);
    liquidityExtension = ILiquidityExtension(_liquidityExtension);
    maltDataLab = IMaltDataLab(_maltDataLab);
    stabilizerNode = IStabilizerNode(_stabilizerNode);
    globalIC = IGlobalImpliedCollateralService(_globalIC);
    collateralToken = ERC20(_collateralToken);
    malt = IBurnMintableERC20(_malt);
    stakeToken = IUniswapV2Pair(_stakeToken);

    (, address updater, ) = poolFactory.getPool(_stakeToken);
    _setPoolUpdater(updater);
  }

  function syncGlobalCollateral() public onlyActive {
    globalIC.sync(getCollateralizedMalt());
  }

  function getCollateralizedMalt() public view returns (PoolCollateral memory) {
    uint256 target = maltDataLab.priceTarget();

    uint256 unity = 10**collateralToken.decimals();

    // Convert all balances to be denominated in units of Malt target price
    uint256 overflowBalance = maltDataLab.rewardToMaltDecimals((collateralToken.balanceOf(
      address(overflowPool)
    ) * unity) / target);
    uint256 liquidityExtensionBalance = (collateralToken.balanceOf(
      address(liquidityExtension)
    ) * unity) / target;
    (
      uint256 swingTraderMaltBalance,
      uint256 swingTraderBalance
    ) = swingTraderManager.getTokenBalances();
    swingTraderBalance = (swingTraderBalance * unity) / target;

    return
      PoolCollateral({
        lpPool: address(stakeToken),
        // Note that swingTraderBalance also includes the overflowBalance
        // Therefore the total doesn't need to include overflowBalance explicitly
        total: maltDataLab.rewardToMaltDecimals(
            liquidityExtensionBalance + swingTraderBalance
        ),
        rewardOverflow: overflowBalance,
        liquidityExtension: maltDataLab.rewardToMaltDecimals(
          liquidityExtensionBalance
        ),
        // This swingTraderBalance value isn't just the capital in the swingTrader
        // contract but also includes what is in the overflow so we subtract that
        swingTrader: maltDataLab.rewardToMaltDecimals(swingTraderBalance) - overflowBalance,
        swingTraderMalt: swingTraderMaltBalance,
        arbTokens: maltDataLab.rewardToMaltDecimals(
          auction.unclaimedArbTokens()
        )
      });
  }

  function totalUsefulCollateral() public view returns (uint256 collateral) {
    uint256 liquidityExtensionBalance = collateralToken.balanceOf(
      address(liquidityExtension)
    );
    (, uint256 swingTraderBalances) = swingTraderManager.getTokenBalances();

    return liquidityExtensionBalance + swingTraderBalances;
  }

  function collateralRatio() external view returns (uint256 icTotal) {
    uint256 decimals = collateralToken.decimals();
    (uint256 reserve0, uint256 reserve1, ) = stakeToken.getReserves();

    uint256 maltInPool = address(malt) < address(collateralToken)
      ? maltDataLab.maltToRewardDecimals(reserve0)
      : maltDataLab.maltToRewardDecimals(reserve1);

    icTotal = ((totalUsefulCollateral() * (10**decimals)) / maltInPool);
  }

  function swingTraderCollateralRatio()
    external
    view
    returns (uint256 icTotal)
  {
    uint256 decimals = collateralToken.decimals();
    uint256 overflowBalance = collateralToken.balanceOf(address(overflowPool));

    // SwingTraderManager will return balance in swing trader as well as overflow
    // So we need to subtract the overflow balance from the swingTraderBalance
    (, uint256 swingTraderBalance) = swingTraderManager.getTokenBalances();
    swingTraderBalance = swingTraderBalance - overflowBalance;

    (uint256 reserve0, uint256 reserve1, ) = stakeToken.getReserves();

    uint256 maltInPool = address(malt) < address(collateralToken)
      ? maltDataLab.maltToRewardDecimals(reserve0)
      : maltDataLab.maltToRewardDecimals(reserve1);

    icTotal = ((swingTraderBalance * (10**decimals)) / maltInPool);
  }

  function _accessControl()
    internal
    override(
      DataLabExtension,
      SwingTraderManagerExtension,
      LiquidityExtensionExtension,
      RewardOverflowExtension,
      AuctionExtension,
      GlobalICExtension,
      StabilizerNodeExtension
    )
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
