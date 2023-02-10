// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IDexHandler {
  function buyMalt(uint256, uint256) external returns (uint256 purchased);

  function sellMalt(uint256, uint256) external returns (uint256 rewards);

  function addLiquidity(
    uint256,
    uint256,
    uint256
  )
    external
    returns (
      uint256 maltUsed,
      uint256 rewardUsed,
      uint256 liquidityCreated
    );

  function removeLiquidity(uint256, uint256)
    external
    returns (uint256 amountMalt, uint256 amountReward);

  function calculateMintingTradeSize(uint256 priceTarget)
    external
    view
    returns (uint256);

  function calculateBurningTradeSize(uint256 priceTarget)
    external
    view
    returns (uint256);

  function reserves()
    external
    view
    returns (uint256 maltSupply, uint256 rewardSupply);

  function maltMarketPrice()
    external
    view
    returns (uint256 price, uint256 decimals);

  function getOptimalLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidityB
  ) external view returns (uint256 liquidityA);

  function setupContracts(
    address,
    address,
    address,
    address,
    address[] memory,
    address[] memory,
    address[] memory,
    address[] memory
  ) external;

  function addBuyer(address) external;

  function removeBuyer(address) external;

  function addSeller(address) external;

  function removeSeller(address) external;

  function addLiquidityAdder(address) external;

  function removeLiquidityAdder(address) external;

  function addLiquidityRemover(address) external;

  function removeLiquidityRemover(address) external;
}
