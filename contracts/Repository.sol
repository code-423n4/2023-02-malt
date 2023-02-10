// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/access/AccessControl.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

struct Contract {
  address contractAddress;
  uint256 index;
}

/// @title Repository
/// @author 0xScotch <scotch@malt.money>
/// @notice A global repository of Malt contracts and global access control
contract MaltRepository is AccessControl {
  using SafeERC20 for ERC20;

  // Timelock has absolute power across the system
  bytes32 public immutable TIMELOCK_ROLE;
  bytes32 public immutable ADMIN_ROLE;
  bytes32 public immutable KEEPER_ROLE;

  mapping(bytes32 => bool) public validRoles;
  mapping(bytes32 => Contract) public globalContracts;
  string[] public contracts;
  address internal immutable deployer;

  event AddRole(bytes32 role);
  event RemoveRole(bytes32 role);
  event AddContract(bytes32 indexed hashedName, address contractAddress);
  event RemoveContract(bytes32 indexed hashedName);
  event UpdateContract(bytes32 indexed hashedName, address contractAddress);

  constructor(address _deployer) {
    // keccak256("TIMELOCK_ROLE");
    TIMELOCK_ROLE = 0xf66846415d2bf9eabda9e84793ff9c0ea96d87f50fc41e66aa16469c6a442f05;
    // keccak256("ADMIN_ROLE");
    ADMIN_ROLE = 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775;
    // keccak256("KEEPER_ROLE");
    KEEPER_ROLE = 0xfc8737ab85eb45125971625a9ebdb75cc78e01d5c1fa80c4c6e5203f47bc4fab;
    deployer = _deployer;
  }

  function setupContracts(
    address _timelock,
    address[] memory _admins,
    address _malt,
    address _timekeeper,
    address _transferService,
    address _globalIC,
    address _poolFactory
  ) external {
    require(msg.sender == deployer, "Must be deployer");
    _setup(_timelock, _admins);
    _contractSetup("timelock", _timelock);
    _contractSetup("malt", _malt);
    _contractSetup("timekeeper", _timekeeper);
    _contractSetup("transferService", _transferService);
    _contractSetup("globalIC", _globalIC);
    _contractSetup("poolFactory", _poolFactory);
  }

  function hasRole(bytes32 role, address account)
    public
    view
    override
    returns (bool)
  {
    // Timelock has all possible permissions
    return
      (super.hasRole(role, account) && validRoles[role]) ||
      super.hasRole(TIMELOCK_ROLE, account);
  }

  function checkRole(string memory _role) public view returns (bool) {
    bytes32 hashedRole = keccak256(abi.encodePacked(_role));
    return validRoles[hashedRole];
  }

  function getContract(string memory _contract) public view returns (address) {
    bytes32 hashedContract = keccak256(abi.encodePacked(_contract));
    return globalContracts[hashedContract].contractAddress;
  }

  function grantRole(bytes32 role, address account)
    public
    override
    onlyRole(getRoleAdmin(role))
  {
    require(validRoles[role], "Unknown role");
    _grantRole(role, account);
  }

  function addNewRole(bytes32 role) external onlyRole(TIMELOCK_ROLE) {
    _roleSetup(role, msg.sender);
  }

  function removeRole(bytes32 role) external onlyRole(getRoleAdmin(role)) {
    validRoles[role] = false;
    emit RemoveRole(role);
  }

  function addNewContract(string memory _name, address _contract)
    external
    onlyRole(TIMELOCK_ROLE)
  {
    _contractSetup(_name, _contract);
  }

  function removeContract(string memory _name)
    external
    onlyRole(TIMELOCK_ROLE)
  {
    _removeContract(_name);
  }

  function updateContract(string memory _name, address _contract)
    external
    onlyRole(TIMELOCK_ROLE)
  {
    _updateContract(_name, _contract);
  }

  function grantRoleMultiple(bytes32 role, address[] calldata addresses)
    external
    onlyRole(getRoleAdmin(role))
  {
    require(validRoles[role], "Unknown role");
    uint256 length = addresses.length; // gas

    for (uint256 i; i < length; ++i) {
      address account = addresses[i];
      require(account != address(0), "0x0");
      _grantRole(role, account);
    }
  }

  function emergencyWithdrawGAS(address payable destination)
    external
    onlyRole(TIMELOCK_ROLE)
  {
    require(destination != address(0), "Withdraw: addr(0)");
    // Transfers the entire balance of the Gas token to destination
    (bool success, ) = destination.call{value: address(this).balance}("");
    require(success, "emergencyWithdrawGAS error");
  }

  function emergencyWithdraw(address _token, address destination)
    external
    onlyRole(TIMELOCK_ROLE)
  {
    require(destination != address(0), "Withdraw: addr(0)");
    // Transfers the entire balance of an ERC20 token at _token to destination
    ERC20 token = ERC20(_token);
    token.safeTransfer(destination, token.balanceOf(address(this)));
  }

  function partialWithdrawGAS(address payable destination, uint256 amount)
    external
    onlyRole(TIMELOCK_ROLE)
  {
    require(destination != address(0), "Withdraw: addr(0)");
    (bool success, ) = destination.call{value: amount}("");
    require(success, "partialWithdrawGAS error");
  }

  function partialWithdraw(
    address _token,
    address destination,
    uint256 amount
  ) external onlyRole(TIMELOCK_ROLE) {
    require(destination != address(0), "Withdraw: addr(0)");
    ERC20 token = ERC20(_token);
    token.safeTransfer(destination, amount);
  }

  /*
   * INTERNAL METHODS
   */
  function _setup(address _timelock, address[] memory _admins) internal {
    _roleSetup(TIMELOCK_ROLE, _timelock);
    _roleSetup(ADMIN_ROLE, _timelock);
    _roleSetup(KEEPER_ROLE, _timelock);

    uint256 length = _admins.length; // gas

    for (uint256 i; i < length; ++i) {
      address account = _admins[i];
      require(account != address(0), "0x0");
      _grantRole(ADMIN_ROLE, account);
      _grantRole(KEEPER_ROLE, account);
    }
  }

  function _transferRole(
    address newAccount,
    address oldAccount,
    bytes32 role
  ) internal {
    _revokeRole(role, oldAccount);
    _grantRole(role, newAccount);
  }

  function _roleSetup(bytes32 role, address account) internal {
    _grantRole(role, account);
    _setRoleAdmin(role, TIMELOCK_ROLE);
    validRoles[role] = true;
    emit AddRole(role);
  }

  function _contractSetup(string memory _name, address _contract) internal {
    require(_contract != address(0), "0x0");
    bytes32 hashedName = keccak256(abi.encodePacked(_name));
    Contract storage currentContract = globalContracts[hashedName];
    currentContract.contractAddress = _contract;
    currentContract.index = contracts.length;
    contracts.push(_name);
    emit AddContract(hashedName, _contract);
  }

  function _removeContract(string memory _name) internal {
    bytes32 hashedName = keccak256(abi.encodePacked(_name));
    Contract storage currentContract = globalContracts[hashedName];
    currentContract.contractAddress = address(0);
    currentContract.index = 0;

    uint256 index = currentContract.index;
    string memory lastContract = contracts[contracts.length - 1];
    contracts[index] = lastContract;
    contracts.pop();
    emit RemoveContract(hashedName);
  }

  function _updateContract(string memory _name, address _newContract) internal {
    require(_newContract != address(0), "0x0");
    bytes32 hashedName = keccak256(abi.encodePacked(_name));
    Contract storage currentContract = globalContracts[hashedName];
    currentContract.contractAddress = _newContract;
    emit UpdateContract(hashedName, _newContract);
  }
}
