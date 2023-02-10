// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../interfaces/IMaltDataLab.sol";
import "../interfaces/IStabilizerNode.sol";
import "../interfaces/IAuction.sol";
import "../Permissions.sol";
import "./AbstractTransferVerification.sol";
import "../StabilizedPoolExtensions/DataLabExtension.sol";
import "../StabilizedPoolExtensions/StabilizerNodeExtension.sol";

/// @title Pool Transfer Verification
/// @author 0xScotch <scotch@malt.money>
/// @notice Implements ability to block Malt transfers
contract PoolTransferVerification is
  AbstractTransferVerification,
  StabilizerNodeExtension,
  DataLabExtension
{
  uint256 public upperThresholdBps;
  uint256 public lowerThresholdBps;
  uint256 public priceLookbackBelow;
  uint256 public priceLookbackAbove;

  bool public paused = true;
  bool internal killswitch = true;

  mapping(address => bool) public whitelist;
  mapping(address => bool) public killswitchAllowlist;

  event AddToWhitelist(address indexed _address);
  event RemoveFromWhitelist(address indexed _address);
  event AddToKillswitchAllowlist(address indexed _address);
  event RemoveFromKillswitchAllowlist(address indexed _address);
  event SetPriceLookbacks(uint256 lookbackUpper, uint256 lookbackLower);
  event SetThresholds(uint256 newUpperThreshold, uint256 newLowerThreshold);
  event SetPaused(bool paused);
  event SetKillswitch(bool killswitch);

  constructor(
    address timelock,
    address repository,
    address poolFactory,
    uint256 _lowerThresholdBps,
    uint256 _upperThresholdBps,
    uint256 _lookbackAbove,
    uint256 _lookbackBelow
  ) AbstractTransferVerification(timelock, repository, poolFactory) {
    lowerThresholdBps = _lowerThresholdBps;
    upperThresholdBps = _upperThresholdBps;
    priceLookbackAbove = _lookbackAbove;
    priceLookbackBelow = _lookbackBelow;
  }

  function setupContracts(
    address _maltDataLab,
    address _stakeToken,
    address _initialWhitelist,
    address _stabilizerNode
  ) external onlyRoleMalt(POOL_FACTORY_ROLE, "Must have pool factory role") {
    require(!contractActive, "XferVerifier: Already setup");
    require(_maltDataLab != address(0), "XferVerifier: DataLab addr(0)");
    require(_stakeToken != address(0), "XferVerifier: StakeToken addr(0)");
    require(_stabilizerNode != address(0), "XferVerifier: StabNode addr(0)");

    contractActive = true;

    maltDataLab = IMaltDataLab(_maltDataLab);
    stakeToken = IUniswapV2Pair(_stakeToken);
    stabilizerNode = IStabilizerNode(_stabilizerNode);

    if (_initialWhitelist != address(0)) {
      whitelist[_initialWhitelist] = true;
    }

    (, address updater, ) = poolFactory.getPool(_stakeToken);
    _setPoolUpdater(updater);
  }

  function verifyTransfer(
    address from,
    address to,
    uint256 amount
  )
    external
    view
    override
    returns (
      bool,
      string memory,
      address,
      bytes memory
    )
  {
    if (killswitch) {
      if (killswitchAllowlist[from] || killswitchAllowlist[to]) {
        return (true, "", address(0), "");
      }
      return (false, "Malt: Pool transfers have been paused", address(0), "");
    }

    if (paused) {
      // This pauses any transfer verifiers. In essence allowing all Malt Txs
      return (true, "", address(0), "");
    }

    if (from != address(stakeToken)) {
      return (true, "", address(0), "");
    }

    if (whitelist[to]) {
      return (true, "", address(0), "");
    }

    return _belowPegCheck();
  }

  function _belowPegCheck()
    internal
    view
    returns (
      bool,
      string memory,
      address,
      bytes memory
    )
  {
    bool result;

    (bool usePrimedWindow, uint256 windowEndBlock) = stabilizerNode
      .primedWindowData();

    if (usePrimedWindow) {
      if (block.number > windowEndBlock) {
        result = true;
      }
    } else {
      uint256 priceTarget = maltDataLab.getActualPriceTarget();

      result =
        maltDataLab.maltPriceAverage(priceLookbackBelow) >
        (priceTarget * (10000 - lowerThresholdBps)) / 10000;
    }

    return (result, "Malt: BELOW PEG", address(0), "");
  }

  function isWhitelisted(address _address) public view returns (bool) {
    return whitelist[_address];
  }

  function isAllowlisted(address _address) public view returns (bool) {
    return killswitchAllowlist[_address];
  }

  /*
   * PRIVILEDGED METHODS
   */
  function setThresholds(uint256 newUpperThreshold, uint256 newLowerThreshold)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(
      newUpperThreshold != 0 && newUpperThreshold < 10000,
      "Upper threshold must be between 0-100%"
    );
    require(
      newLowerThreshold != 0 && newLowerThreshold < 10000,
      "Lower threshold must be between 0-100%"
    );
    upperThresholdBps = newUpperThreshold;
    lowerThresholdBps = newLowerThreshold;
    emit SetThresholds(newUpperThreshold, newLowerThreshold);
  }

  function setPriceLookback(uint256 lookbackAbove, uint256 lookbackBelow)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(lookbackAbove != 0 && lookbackBelow != 0, "Cannot have 0 lookback");
    priceLookbackAbove = lookbackAbove;
    priceLookbackBelow = lookbackBelow;
    emit SetPriceLookbacks(lookbackAbove, lookbackBelow);
  }

  function addToWhitelist(address _address)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role")
  {
    whitelist[_address] = true;
    emit AddToWhitelist(_address);
  }

  function removeFromWhitelist(address _address)
    external
    onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role")
  {
    if (!whitelist[_address]) {
      return;
    }
    whitelist[_address] = false;
    emit RemoveFromWhitelist(_address);
  }

  function addToAllowlist(address _address)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    killswitchAllowlist[_address] = true;
    emit AddToKillswitchAllowlist(_address);
  }

  function removeFromAllowlist(address _address)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    if (!killswitchAllowlist[_address]) {
      return;
    }
    killswitchAllowlist[_address] = false;
    emit RemoveFromKillswitchAllowlist(_address);
  }

  function togglePause()
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    bool localPaused = paused;
    paused = !localPaused;
    emit SetPaused(localPaused);
  }

  function toggleKillswitch()
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    bool localKillswitch = killswitch;
    killswitch = !localKillswitch;
    emit SetKillswitch(!localKillswitch);
  }

  function _accessControl()
    internal
    override(DataLabExtension, StabilizerNodeExtension)
  {
    _onlyRoleMalt(POOL_UPDATER_ROLE, "Must have pool updater role");
  }
}
