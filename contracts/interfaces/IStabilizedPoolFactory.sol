// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../StabilizedPool/StabilizedPool.sol";

interface IStabilizedPoolFactory {
  function getPool(address pool)
    external
    view
    returns (
      address collateralToken,
      address updater,
      string memory name
    );

  function getPeripheryContracts(address pool)
    external
    view
    returns (
      address dataLab,
      address dexHandler,
      address transferVerifier,
      address keeper,
      address dualMA
    );

  function getRewardSystemContracts(address pool)
    external
    view
    returns (
      address vestingDistributor,
      address linearDistributor,
      address rewardOverflow,
      address rewardThrottle
    );

  function getStakingContracts(address pool)
    external
    view
    returns (
      address bonding,
      address miningService,
      address vestedMine,
      address forfeitHandler,
      address linearMine,
      address reinvestor
    );

  function getCoreContracts(address pool)
    external
    view
    returns (
      address auction,
      address auctionEscapeHatch,
      address impliedCollateralService,
      address liquidityExtension,
      address profitDistributor,
      address stabilizerNode,
      address swingTrader,
      address swingTraderManager
    );

  function getStabilizedPool(address)
    external
    view
    returns (StabilizedPool memory);

  function setCurrentPool(address, StabilizedPool memory) external;
}
