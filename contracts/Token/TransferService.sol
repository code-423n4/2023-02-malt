// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "openzeppelin/utils/structs/EnumerableSet.sol";

import "../interfaces/IMaltDataLab.sol";
import "../interfaces/ITransferService.sol";
import "../Permissions.sol";

import "../interfaces/ITransferVerification.sol";

/// @title Transfer Service
/// @author 0xScotch <scotch@malt.money>
/// @notice A contract that acts like a traffic warden to ensure tranfer verification requests get routed correctly
contract TransferService is Permissions, ITransferService {
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public immutable VERIFIER_MANAGER_ROLE;

  address public verifierManager;
  address public proposedManager;
  address internal immutable deployer;

  EnumerableSet.AddressSet private verifierSet;
  mapping(address => address) public verifiers;

  event AddVerifier(address indexed source, address verifier);
  event RemoveVerifier(address indexed source, address verifier);
  event ProposeVerifierManager(address manager);
  event ChangeVerifierManager(address manager);

  constructor(
    address _repository,
    address initialAdmin,
    address _deployer
  ) {
    require(_repository != address(0), "XferSvc: Repo addr(0)");
    require(initialAdmin != address(0), "XferSvc: Admin addr(0)");
    _initialSetup(_repository);
    VERIFIER_MANAGER_ROLE = 0x4836742ac1468da85cb088467781b7828a2a2c1cbdbf314f2ad90d18c4d9b6c6;
    _roleSetup(
      0x4836742ac1468da85cb088467781b7828a2a2c1cbdbf314f2ad90d18c4d9b6c6,
      initialAdmin
    );

    deployer = _deployer;
  }

  function verifyTransferAndCall(
    address from,
    address to,
    uint256 amount
  ) external returns (bool, string memory) {
    (
      bool valid,
      string memory reason,
      address[2] memory targets,
      bytes[2] memory data
    ) = verifyTransfer(from, to, amount);

    if (!valid) {
      return (false, reason);
    }

    if (targets[0] != address(0)) {
      (bool success, bytes memory data) = targets[0].call(data[0]);
      require(success, "TransferService: External failure");
    }

    if (targets[1] != address(0)) {
      (bool success, bytes memory data) = targets[1].call(data[1]);
      require(success, "TransferService: External failure");
    }

    return (true, "");
  }

  function verifyTransfer(
    address from,
    address to,
    uint256 amount
  )
    public
    view
    returns (
      bool,
      string memory,
      address[2] memory,
      bytes[2] memory
    )
  {
    address[2] memory targets;
    bytes[2] memory datalist;

    if (verifiers[from] != address(0)) {
      (
        bool valid,
        string memory reason,
        address target,
        bytes memory data
      ) = ITransferVerification(verifiers[from]).verifyTransfer(
          from,
          to,
          amount
        );

      if (!valid) {
        return (false, reason, targets, datalist);
      }
      targets[0] = target;
      datalist[0] = data;
    }

    if (verifiers[to] != address(0)) {
      (
        bool valid,
        string memory reason,
        address target,
        bytes memory data
      ) = ITransferVerification(verifiers[to]).verifyTransfer(from, to, amount);

      if (!valid) {
        return (false, reason, targets, datalist);
      }
      targets[1] = target;
      datalist[1] = data;
    }

    return (true, "", targets, datalist);
  }

  function numberOfVerifiers() public view returns (uint256) {
    return verifierSet.length();
  }

  function getVerifierByIndex(uint256 index)
    external
    view
    returns (address target, address verifier)
  {
    target = verifierSet.at(index);
    verifier = verifiers[target];
  }

  /*
   * PRIVILEDGED METHODS
   */
  function addVerifier(address _address, address _verifier)
    external
    onlyRoleMalt(VERIFIER_MANAGER_ROLE, "Must have verifier manager role")
  {
    require(_verifier != address(0), "Cannot use address 0");
    require(_address != address(0), "Cannot use address 0");

    require(verifiers[_address] == address(0), "Address already exists");

    verifiers[_address] = _verifier;
    verifierSet.add(_address);

    emit AddVerifier(_address, _verifier);
  }

  function removeVerifier(address _address)
    external
    onlyRoleMalt(VERIFIER_MANAGER_ROLE, "Must have verifier manager role")
  {
    require(_address != address(0), "Cannot use address 0");
    require(verifiers[_address] != address(0), "Address does not exists");

    // not possible to remove as RemoveVerifier uses old and new
    address verifier = verifiers[_address];
    verifiers[_address] = address(0);
    verifierSet.remove(_address);

    emit RemoveVerifier(_address, verifier);
  }

  /// @notice Privileged method for setting the initial verifier manager
  /// @param _verifierManager The address of the new manager
  function setVerifierManager(address _verifierManager) external {
    require(msg.sender == deployer, "Only deployer");
    require(_verifierManager != address(0), "Cannot use addr(0)");
    require(verifierManager == address(0), "Initial verifier already set");
    verifierManager = _verifierManager;
    _grantRole(VERIFIER_MANAGER_ROLE, _verifierManager);
  }

  /// @notice Privileged method for proposing a new verifier manager
  /// @param _verifierManager The address of the newly proposed manager contract
  /// @dev Only callable via the existing verifier manager contract
  function proposeNewVerifierManager(address _verifierManager)
    external
    onlyRoleMalt(VERIFIER_MANAGER_ROLE, "Must have pool factory role")
  {
    require(_verifierManager != address(0), "Cannot use addr(0)");
    proposedManager = _verifierManager;
    emit ProposeVerifierManager(_verifierManager);
  }

  /// @notice Method for a proposed verifier manager contract to accept the role
  /// @dev Only callable via the proposedManager
  function acceptVerifierManagerRole() external {
    require(msg.sender == proposedManager, "Must be proposedManager");
    _transferRole(proposedManager, verifierManager, VERIFIER_MANAGER_ROLE);
    proposedManager = address(0);
    verifierManager = msg.sender;
    emit ChangeVerifierManager(msg.sender);
  }
}
