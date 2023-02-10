pragma solidity 0.8.11;

interface IKeeperCompatibleInterface {
  function checkUpkeep(bytes calldata checkData)
    external
    returns (bool upkeepNeeded, bytes memory performData);

  function performUpkeep(bytes calldata performData) external;

  function setupContracts(
    address,
    address,
    address,
    address,
    address,
    address,
    address,
    address
  ) external;

  function setTreasury(address payable) external;

  function togglePaused() external;
}
