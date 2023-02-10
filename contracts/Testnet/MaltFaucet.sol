// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IBurnMintableERC20.sol";
import "../interfaces/IGlobalImpliedCollateralService.sol";
import "../interfaces/IImpliedCollateralService.sol";

interface IFaucet {
  function faucet(uint256) external;
}

contract MaltFaucet {
  IFaucet public collateralFaucetContract;
  IBurnMintableERC20 public malt;
  IBurnMintableERC20 public collateral;
  IGlobalImpliedCollateralService public globalIC;
  IImpliedCollateralService public impliedCollateralService;

  address public swingTrader;
  address public rewardOverflow;

  constructor(
    address _faucet,
    address _malt,
    address _collateral,
    address _globalIC,
    address _impliedCollateralService,
    address _swingTrader,
    address _rewardOverflow
  ) {
    collateralFaucetContract = IFaucet(_faucet);
    malt = IBurnMintableERC20(_malt);
    collateral = IBurnMintableERC20(_collateral);
    globalIC = IGlobalImpliedCollateralService(_globalIC);
    impliedCollateralService = IImpliedCollateralService(
      _impliedCollateralService
    );
    swingTrader = _swingTrader;
    rewardOverflow = _rewardOverflow;
  }

  function faucet(uint256 amount, bool fillCollateral) external {
    uint256 ratio = globalIC.collateralRatio();

    if (ratio == 0) {
      ratio = 10**18;
    }

    malt.mint(msg.sender, amount);

    if (fillCollateral) {
      // Mint collateral equivalent to current collateral ratio
      // This ensures that the collateral ratio constant despite minting fresh malt
      collateralFaucetContract.faucet((amount * ratio) / (10**18));

      uint256 balance = collateral.balanceOf(address(this));

      // Split it between swing trader and reward runway
      uint256 stBalance = collateral.balanceOf(swingTrader);
      uint256 runwayBalance = collateral.balanceOf(rewardOverflow);
      uint256 total = stBalance + runwayBalance;

      uint256 stShare = balance;

      if (total > 0) {
        stShare = (balance * stBalance) / total;
      }

      uint256 runwayShare = balance - stShare;

      collateral.transfer(swingTrader, stShare);
      collateral.transfer(rewardOverflow, runwayShare);
      impliedCollateralService.syncGlobalCollateral();
    }
  }
}
