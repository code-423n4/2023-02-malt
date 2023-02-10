// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;
pragma experimental ABIEncoderV2;

import "openzeppelin/token/ERC20/ERC20.sol";

import "./interfaces/IBurnMintableERC20.sol";
import "./Permissions.sol";

/// @title Malt Timekeeper
/// @author 0xScotch <scotch@malt.money>
/// @notice In essence a contract that is the oracle for the current epoch
contract MaltTimekeeper is Permissions {
  IBurnMintableERC20 public malt;
  uint256 public epoch = 0;
  uint256 public epochLength;
  uint256 public immutable genesisTime;
  uint256 public advanceIncentive = 100; // 100 Malt
  uint256 public timeZero;

  event Advance(uint256 indexed epoch);
  event SetEpochLength(uint256 length);
  event SetAdvanceIncentive(uint256 incentive);

  constructor(
    address _repository,
    uint256 _epochLength,
    uint256 _genesisTime,
    address _malt
  ) {
    require(_repository != address(0), "DAO: Timelock addr(0)");
    require(_malt != address(0), "DAO: Malt addr(0)");
    epochLength = _epochLength;
    emit SetEpochLength(_epochLength);

    _initialSetup(_repository);

    genesisTime = _genesisTime;
    timeZero = _genesisTime;
    malt = IBurnMintableERC20(_malt);
  }

  receive() external payable {}

  function advance() external {
    require(
      block.timestamp >= getEpochStartTime(epoch + 1),
      "Cannot advance epoch until start of new epoch"
    );

    epoch += 1;

    malt.mint(msg.sender, advanceIncentive * (10**malt.decimals()));

    emit Advance(epoch);
  }

  function getEpochStartTime(uint256 _epoch) public view returns (uint256) {
    return timeZero + (epochLength * _epoch);
  }

  function epochsPerYear() public view returns (uint256) {
    // 31557600 = seconds in a year
    return 31557600 / epochLength;
  }

  function setEpochLength(uint256 _length)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(_length > 0, "Cannot have zero length epochs");
    require(_length != epochLength, "Length must be different");

    // Reset time so that epochStartTime is calculated correctly for the new epoch length
    // This also makes current time the start of the epoch
    timeZero = block.timestamp - (_length * epoch);

    epochLength = _length;
    emit SetEpochLength(_length);
  }

  function setAdvanceIncentive(uint256 incentive)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin role")
  {
    require(incentive <= 1000, "Incentive cannot be more than 1000 Malt");
    advanceIncentive = incentive;
    emit SetAdvanceIncentive(incentive);
  }
}
