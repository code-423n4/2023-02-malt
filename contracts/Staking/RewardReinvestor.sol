// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IDexHandler.sol";
import "../interfaces/IBonding.sol";
import "../interfaces/IMiningService.sol";
import "../libraries/uniswap/Babylonian.sol";
import "../libraries/UniswapV2Library.sol";
import "../libraries/SafeBurnMintableERC20.sol";
import "../StabilizedPoolExtensions/StabilizedPoolUnit.sol";
import "../StabilizedPoolExtensions/BondingExtension.sol";
import "../StabilizedPoolExtensions/DexHandlerExtension.sol";
import "../StabilizedPoolExtensions/MiningServiceExtension.sol";

/// @title Reward Reinvestor
/// @author 0xScotch <scotch@malt.money>
/// @notice Provide a way to programmatically reinvest Malt rewards
contract RewardReinvestor is
  StabilizedPoolUnit,
  BondingExtension,
  DexHandlerExtension,
  MiningServiceExtension
{
  using SafeERC20 for ERC20;
  using SafeBurnMintableERC20 for IBurnMintableERC20;

  ERC20 public lpToken;

  address public treasury;

  event ProvideReinvest(address account, uint256 reward);
  event SplitReinvest(address account, uint256 amountReward);
  event SetTreasury(address _treasury);

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    address _treasury
  ) StabilizedPoolUnit(timelock, repository, poolFactory) {
    require(_treasury != address(0), "Reinvestor: Treasury addr(0)");

    treasury = _treasury;
  }

  function setupContracts(
    address _malt,
    address _collateralToken,
    address _dexHandler,
    address _bonding,
    address _lpToken,
    address _miningService
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role") {
    require(!contractActive, "Reinvestor: Already setup");
    require(_malt != address(0), "Reinvestor: Malt addr(0)");
    require(_collateralToken != address(0), "Reinvestor: Col addr(0)");
    require(_dexHandler != address(0), "Reinvestor: DexHandler addr(0)");
    require(_bonding != address(0), "Reinvestor: Bonding addr(0)");
    require(_miningService != address(0), "Reinvestor: MiningSvc addr(0)");

    contractActive = true;

    malt = IBurnMintableERC20(_malt);
    collateralToken = ERC20(_collateralToken);
    lpToken = ERC20(_lpToken);
    dexHandler = IDexHandler(_dexHandler);
    bonding = IBonding(_bonding);
    miningService = IMiningService(_miningService);

    (, address updater, ) = poolFactory.getPool(_lpToken);
    _setPoolUpdater(updater);
  }

  function provideReinvest(
    uint256 poolId,
    uint256 rewardLiquidity,
    uint256 maltLiquidity,
    uint256 slippageBps
  ) external nonReentrant onlyActive {
    uint256 rewardBalance = _retrieveReward(rewardLiquidity, poolId);

    // Transfer the remaining Malt required
    malt.safeTransferFrom(msg.sender, address(this), maltLiquidity);

    _bondAccount(msg.sender, poolId, maltLiquidity, rewardBalance, slippageBps);

    emit ProvideReinvest(msg.sender, rewardBalance);
  }

  function splitReinvest(
    uint256 poolId,
    uint256 rewardLiquidity,
    uint256 rewardReserves,
    uint256 slippageBps
  ) external nonReentrant onlyActive {
    uint256 rewardBalance = _retrieveReward(rewardLiquidity, poolId);
    uint256 swapAmount = _optimalLiquiditySwap(rewardBalance, rewardReserves);

    collateralToken.safeTransfer(address(dexHandler), swapAmount);
    uint256 amountMalt = dexHandler.buyMalt(swapAmount, slippageBps);

    _bondAccount(
      msg.sender,
      poolId,
      amountMalt,
      rewardBalance - swapAmount,
      slippageBps
    );

    emit SplitReinvest(msg.sender, rewardLiquidity);
  }

  function _retrieveReward(uint256 rewardLiquidity, uint256 poolId)
    internal
    returns (uint256)
  {
    require(rewardLiquidity > 0, "Cannot reinvest 0");

    miningService.withdrawRewardsForAccount(
      msg.sender,
      poolId,
      rewardLiquidity
    );

    return collateralToken.balanceOf(address(this));
  }

  function _bondAccount(
    address account,
    uint256 poolId,
    uint256 amountMalt,
    uint256 amountReward,
    uint256 slippageBps
  ) internal {
    // It is assumed that the calling functions have ensured
    // The token balances are correct
    malt.safeTransfer(address(dexHandler), amountMalt);
    collateralToken.safeTransfer(address(dexHandler), amountReward);

    (, , uint256 liquidityCreated) = dexHandler.addLiquidity(
      amountMalt,
      amountReward,
      slippageBps
    );

    // Ensure starting from 0
    lpToken.safeApprove(address(bonding), 0);
    lpToken.safeApprove(address(bonding), liquidityCreated);

    bonding.bondToAccount(account, poolId, liquidityCreated);

    // Reset approval
    lpToken.safeApprove(address(bonding), 0);

    // If there is any carry / left overs then send to treasury
    uint256 maltBalance = malt.balanceOf(address(this));
    uint256 rewardTokenBalance = collateralToken.balanceOf(address(this));

    if (maltBalance > 0) {
      malt.safeTransfer(treasury, maltBalance);
    }

    if (rewardTokenBalance > 0) {
      collateralToken.safeTransfer(treasury, rewardTokenBalance);
    }
  }

  function _optimalLiquiditySwap(uint256 amountA, uint256 reserveA)
    internal
    pure
    returns (uint256)
  {
    // assumes 0.3% fee
    return ((Babylonian.sqrt(
      reserveA * ((amountA * 3988000) + (reserveA * 3988009))
    ) - (reserveA * 1997)) / 1994);
  }

  function setTreasury(address _treasury)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role")
  {
    require(_treasury != address(0), "Not address 0");
    treasury = _treasury;
    emit SetTreasury(_treasury);
  }

  function _accessControl()
    internal
    override(BondingExtension, DexHandlerExtension, MiningServiceExtension)
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
