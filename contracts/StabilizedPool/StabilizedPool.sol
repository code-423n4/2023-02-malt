// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

struct Core {
  address auction;
  address auctionEscapeHatch;
  address impliedCollateralService;
  address liquidityExtension;
  address profitDistributor;
  address stabilizerNode;
  address swingTrader;
  address swingTraderManager;
}

struct Staking {
  address bonding;
  address miningService;
  address vestedMine;
  address forfeitHandler;
  address linearMine;
  address reinvestor;
}

struct RewardSystem {
  address vestingDistributor;
  address linearDistributor;
  address rewardOverflow;
  address rewardThrottle;
}

struct Periphery {
  address dataLab;
  address dexHandler;
  address transferVerifier;
  address keeper;
  address dualMA;
  address swingTraderMaltRatioMA;
}

struct StabilizedPool {
  Core core;
  Staking staking;
  RewardSystem rewardSystem;
  Periphery periphery;
  address collateralToken;
  address pool;
  address updater;
  string name;
}
