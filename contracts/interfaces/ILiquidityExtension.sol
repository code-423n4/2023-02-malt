// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ILiquidityExtension {
  function hasMinimumReserves() external view returns (bool);

  function collateralDeficit() external view returns (uint256, uint256);

  function reserveRatio() external view returns (uint256, uint256);

  function reserveRatioAverage(uint256)
    external
    view
    returns (uint256, uint256);

  function purchaseAndBurn(uint256 amount) external returns (uint256 purchased);

  function allocateBurnBudget(uint256 amount) external;

  function buyBack(uint256 maltAmount) external;
}
