// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IGlobalImpliedCollateralService.sol";
import "./IMovingAverage.sol";

interface IMaltDataLab {
  function priceTarget() external view returns (uint256);

  function smoothedMaltPrice() external view returns (uint256);

  function globalIC() external view returns (IGlobalImpliedCollateralService);

  function smoothedK() external view returns (uint256);

  function smoothedReserves() external view returns (uint256);

  function maltPriceAverage(uint256 _lookback) external view returns (uint256);

  function kAverage(uint256 _lookback) external view returns (uint256);

  function poolReservesAverage(uint256 _lookback)
    external
    view
    returns (uint256, uint256);

  function lastMaltPrice() external view returns (uint256, uint64);

  function lastPoolReserves()
    external
    view
    returns (
      uint256,
      uint256,
      uint64
    );

  function lastK() external view returns (uint256, uint64);

  function realValueOfLPToken(uint256 amount) external view returns (uint256);

  function trackPool() external returns (bool);

  function trustedTrackPool(
    uint256,
    uint256,
    uint256,
    uint256
  ) external;

  function collateralToken() external view returns (address);

  function malt() external view returns (address);

  function stakeToken() external view returns (address);

  function getInternalAuctionEntryPrice()
    external
    view
    returns (uint256 auctionEntryPrice);

  function getSwingTraderEntryPrice()
    external
    view
    returns (uint256 stPriceTarget);

  function getActualPriceTarget() external view returns (uint256);

  function getRealBurnBudget(uint256, uint256) external view returns (uint256);

  function maltToRewardDecimals(uint256 maltAmount)
    external
    view
    returns (uint256);

  function rewardToMaltDecimals(uint256 amount) external view returns (uint256);

  function smoothedMaltRatio() external view returns (uint256);

  function ratioMA() external view returns (IMovingAverage);

  function trustedTrackMaltRatio(uint256) external;
}
