// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./MaltTest.sol";
import "../contracts/StabilityPod/SwingTraderManager.sol";
import "../contracts/StabilityPod/SwingTrader.sol";


contract SwingTraderManagerTest is MaltTest {
  SwingTraderManager swingTraderManager;

  address poolFactory = nextAddress();
  address stabilizerNode = nextAddress();
  address maltDataLab = nextAddress();
  address swingTrader = nextAddress();
  address rewardOverflow = nextAddress();
  address lpToken = nextAddress();
  address updater = nextAddress();

  function setUp() public {
    swingTraderManager = new SwingTraderManager(
      timelock,
      address(repository),
      poolFactory
    );

    vm.mockCall(
      poolFactory,
      abi.encodeWithSelector(IStabilizedPoolFactory.getPool.selector, lpToken),
      abi.encode(address(0), updater, "")
    );

    vm.prank(admin);
    address[] memory admins = new address[](1);
    admins[0] = admin;
    repository.setupContracts(
      timelock,
      admins,
      address(malt),
      address(1),
      address(transferService),
      address(1),
      address(1)
    );
  }

  function _setupContract() internal {
    vm.prank(poolFactory);
    swingTraderManager.setupContracts(
      address(rewardToken),
      address(malt),
      stabilizerNode,
      maltDataLab,
      swingTrader,
      rewardOverflow,
      lpToken
    );
  }

  function testBuyMaltReturnsZeroForZeroInput() public {
    _setupContract();
    vm.expectRevert("Must have stabilizer node privs");
    uint256 used = swingTraderManager.buyMalt(0);

    vm.prank(stabilizerNode);
    used = swingTraderManager.buyMalt(0);
    assertEq(used, 0);
  }

  function testBuyMaltReturnsZeroWhenNoTradersHaveCapital(uint256 amount) public {
    _setupContract();
    vm.prank(stabilizerNode);
    uint256 used = swingTraderManager.buyMalt(amount);
    assertEq(used, 0);
  }

  function testBuyMalt(uint256 amount) public {
    _setupContract();
    amount = bound(amount, 10000, 2**100);

    mintRewardToken(swingTrader, amount);

    vm.prank(stabilizerNode);
    // swingTrader.buyMalt isn't mocked so it will fail initially
    vm.expectRevert();
    uint256 used = swingTraderManager.buyMalt(amount);

    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(SwingTrader.buyMalt.selector, amount),
      abi.encode(amount)
    );

    vm.prank(stabilizerNode);
    used = swingTraderManager.buyMalt(amount);
    assertEq(used, amount);
  }

  function testBuyMaltOnlyOverflow(uint256 amount) public {
    _setupContract();
    amount = bound(amount, 10000, 2**100);

    mintRewardToken(rewardOverflow, amount);
    
    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(SwingTrader.buyMalt.selector, amount),
      abi.encode(0)
    );

    vm.prank(stabilizerNode);
    // rewardOverflow.buyMalt isn't mocked so it will fail initially
    vm.expectRevert();
    uint256 used = swingTraderManager.buyMalt(amount);

    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(SwingTrader.buyMalt.selector, amount),
      abi.encode(amount)
    );

    vm.prank(stabilizerNode);
    used = swingTraderManager.buyMalt(amount);
    assertEq(used, amount);
  }

  function testBuyMaltMultiplerTraders(uint256 swingTraderAmount, uint256 overflowAmount) public {
    _setupContract();
    swingTraderAmount = bound(swingTraderAmount, 10000, 2**100);
    overflowAmount = bound(overflowAmount, 10000, 2**100);

    uint256 total = swingTraderAmount + overflowAmount;

    mintRewardToken(swingTrader, swingTraderAmount);
    mintRewardToken(rewardOverflow, overflowAmount);

    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(SwingTrader.buyMalt.selector, swingTraderAmount),
      abi.encode(swingTraderAmount)
    );

    vm.prank(stabilizerNode);
    // rewardOverflow.buyMalt isn't mocked so it will fail initially
    vm.expectRevert();
    uint256 used = swingTraderManager.buyMalt(total);

    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(SwingTrader.buyMalt.selector, overflowAmount),
      abi.encode(overflowAmount)
    );

    vm.prank(stabilizerNode);
    used = swingTraderManager.buyMalt(total);
    assertEq(used, total);
  }

  function testCostBasis(uint256 swingTraderAmount, uint256 overflowAmount, uint256 costBasisBps) public {
    _setupContract();
    swingTraderAmount = bound(swingTraderAmount, 10000, 2**100);
    overflowAmount = bound(overflowAmount, 10000, 2**100);
    costBasisBps = bound(costBasisBps, 1, 10000);

    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(ISwingTrader.deployedCapital.selector),
      abi.encode(0)
    );
    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(ISwingTrader.deployedCapital.selector),
      abi.encode(0)
    );

    (uint256 costBasis,) = swingTraderManager.costBasis();
    assertEq(costBasis, 0);

    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(ISwingTrader.deployedCapital.selector),
      abi.encode(swingTraderAmount)
    );
    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(ISwingTrader.deployedCapital.selector),
      abi.encode(overflowAmount)
    );

    mintMalt(swingTrader, swingTraderAmount * 10000 / costBasisBps);
    mintMalt(rewardOverflow, overflowAmount * 10000 / costBasisBps);

    uint256 total = swingTraderAmount + overflowAmount;
    uint256 totalMalt = total * 10000 / costBasisBps;

    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(MaltDataLab.maltToRewardDecimals.selector),
      abi.encode(totalMalt)
    );

    (costBasis,) = swingTraderManager.costBasis();
    assertApproxEqRel(costBasis, 1e18 * costBasisBps / 10000, 1e15); // 0.1%
  }

  function testDeployedCapital(uint256 swingTraderAmount, uint256 overflowAmount) public {
    _setupContract();
    swingTraderAmount = bound(swingTraderAmount, 10000, 2**100);
    overflowAmount = bound(overflowAmount, 10000, 2**100);

    uint256 total = swingTraderAmount + overflowAmount;

    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(ISwingTrader.deployedCapital.selector),
      abi.encode(swingTraderAmount)
    );
    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(ISwingTrader.deployedCapital.selector),
      abi.encode(overflowAmount)
    );

    uint256 deployedCapital = swingTraderManager.deployedCapital();

    assertEq(deployedCapital, total);
  }

  function testSetDustThreshold(uint256 threshold) public {
    _setupContract();
    vm.expectRevert("Must have admin role");
    swingTraderManager.setDustThreshold(threshold);

    uint256 thresh = swingTraderManager.dustThreshold();
    assertEq(thresh, 1e18);

    vm.prank(admin);
    swingTraderManager.setDustThreshold(threshold);

    thresh = swingTraderManager.dustThreshold();
    assertEq(thresh, threshold);
  }

  function testCalculateSwingTraderMaltRatio(uint256 swingTraderAmount, uint256 overflowAmount, uint256 desiredMaltRatioBps) public {
    _setupContract();
    swingTraderAmount = bound(swingTraderAmount, 10000, 2**100);
    overflowAmount = bound(overflowAmount, 10000, 2**100);
    desiredMaltRatioBps = bound(desiredMaltRatioBps, 0, 5000);

    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.priceTarget.selector),
      abi.encode(1e18)
    );
    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.maltToRewardDecimals.selector, 0),
      abi.encode(0)
    );

    uint256 maltRatio = swingTraderManager.calculateSwingTraderMaltRatio();
    assertEq(maltRatio, 0);

    mintRewardToken(swingTrader, swingTraderAmount);
    mintRewardToken(rewardOverflow, overflowAmount);

    uint256 stRatio = 10000 - desiredMaltRatioBps;

    uint256 swingTraderMalt = (swingTraderAmount * 10000 / stRatio) - swingTraderAmount;
    uint256 rewardOverflowMalt = (overflowAmount * 10000 / stRatio) - overflowAmount;
    uint256 totalMalt = swingTraderMalt + rewardOverflowMalt;

    mintMalt(swingTrader, (swingTraderAmount * 10000 / stRatio) - swingTraderAmount);
    mintMalt(rewardOverflow, (overflowAmount * 10000 / stRatio) - overflowAmount);

    vm.mockCall(
      maltDataLab,
      abi.encodeWithSelector(IMaltDataLab.maltToRewardDecimals.selector, totalMalt),
      abi.encode(totalMalt)
    );

    maltRatio = swingTraderManager.calculateSwingTraderMaltRatio();
    assertApproxEqRel(maltRatio, 1e18 * desiredMaltRatioBps / 10000, 1e16); // 1%
  }

  function testGetTotalBalances(
    uint256 swingTraderAmount,
    uint256 overflowAmount,
    uint256 swingTraderMalt,
    uint256 overflowMalt
  ) public {
    _setupContract();
    swingTraderAmount = bound(swingTraderAmount, 0, 2**100);
    overflowAmount = bound(overflowAmount, 0, 2**100);
    swingTraderMalt = bound(swingTraderMalt, 0, 2**100);
    overflowMalt = bound(overflowMalt, 0, 2**100);

    mintRewardToken(swingTrader, swingTraderAmount);
    mintRewardToken(rewardOverflow, overflowAmount);
    mintMalt(swingTrader, swingTraderMalt);
    mintMalt(rewardOverflow, overflowMalt);

    (uint256 maltBalance, uint256 rewardBalance) = swingTraderManager.getTokenBalances();

    assertEq(maltBalance, swingTraderMalt + overflowMalt);
    assertEq(rewardBalance, swingTraderAmount + overflowAmount);
  }

  function testToggleTraderActive() public {
    _setupContract();
    // toggleTraderActive
    (
      uint256 id,
      uint256 index,
      address traderContract,
      string memory name,
      bool active
    ) = swingTraderManager.swingTraders(1);
    assertEq(id, 1);
    assertEq(index, 0);
    assertEq(traderContract, address(swingTrader));
    assertEq(name, "CoreSwingTrader");
    assertEq(active, true);

    vm.expectRevert("Must have admin privs");
    swingTraderManager.toggleTraderActive(1);
    vm.prank(admin);
    swingTraderManager.toggleTraderActive(1);

    (,,,,active) = swingTraderManager.swingTraders(1);
    assertEq(active, false);

    vm.prank(admin);
    swingTraderManager.toggleTraderActive(1);

    (,,,,active) = swingTraderManager.swingTraders(1);
    assertEq(active, true);
  }

  function testAddSwingTraderFailsForExisting() public {
    _setupContract();
    vm.prank(admin);
    vm.expectRevert("TraderId already used");
    swingTraderManager.addSwingTrader(0, address(1234), true, "Test");
  }

  function testAddSwingTraderFailsForAddrZero() public {
    _setupContract();
    vm.prank(admin);
    vm.expectRevert("addr(0)");
    swingTraderManager.addSwingTrader(3, address(0), true, "Test");
  }

  function testAddSwingTrader(address newSwingTrader) public {
    _setupContract();
    vm.assume(newSwingTrader != address(0));
    vm.prank(admin);
    swingTraderManager.addSwingTrader(3, newSwingTrader, true, "Test");

    (
      uint256 id,
      uint256 index,
      address traderContract,
      string memory name,
      bool active
    ) = swingTraderManager.swingTraders(3);

    assertEq(id, 3);
    assertEq(index, 2);
    assertEq(traderContract, newSwingTrader);
    assertEq(name, "Test");
    assertEq(active, true);
  }

  function testSellMaltReturnsZeroForZeroInput() public {
    _setupContract();
    vm.expectRevert("Must have stabilizer node privs");
    uint256 used = swingTraderManager.sellMalt(0);

    vm.prank(stabilizerNode);
    used = swingTraderManager.sellMalt(0);
    assertEq(used, 0);
  }

  function testSellMaltReturnsZeroWhenNoTradersHaveCapital(uint256 amount) public {
    _setupContract();
    vm.prank(stabilizerNode);
    uint256 used = swingTraderManager.sellMalt(amount);
    assertEq(used, 0);
  }

  function testSellMalt(uint256 amount) public {
    _setupContract();
    amount = bound(amount, 10000, 2**100);

    mintMalt(swingTrader, amount);

    vm.prank(stabilizerNode);
    // swingTrader.sellMalt isn't mocked so it will fail initially
    vm.expectRevert();
    uint256 used = swingTraderManager.sellMalt(amount);

    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(ISwingTrader.sellMalt.selector, amount),
      abi.encode(amount)
    );
    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(ISwingTrader.totalProfit.selector),
      abi.encode(0)
    );

    vm.prank(stabilizerNode);
    used = swingTraderManager.sellMalt(amount);
    assertEq(used, amount);
  }

  function testSellMaltOnlyOverflow(uint256 amount) public {
    _setupContract();
    amount = bound(amount, 10000, 2**100);

    mintMalt(rewardOverflow, amount);
    
    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(ISwingTrader.totalProfit.selector),
      abi.encode(0)
    );
    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(ISwingTrader.totalProfit.selector),
      abi.encode(0)
    );
    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(SwingTrader.sellMalt.selector, amount),
      abi.encode(amount)
    );

    vm.prank(stabilizerNode);
    uint256 used = swingTraderManager.sellMalt(amount);

    assertEq(used, amount);
  }

  function testSellMaltOnlyPartiallyFunded(uint256 amount) public {
    _setupContract();
    amount = bound(amount, 10000, 2**100);

    vm.prank(admin);
    swingTraderManager.setDustThreshold(0);

    // Mint less than required
    uint256 actualAmount = amount / 2;
    mintMalt(rewardOverflow, actualAmount);
    
    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(ISwingTrader.totalProfit.selector),
      abi.encode(0)
    );
    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(ISwingTrader.totalProfit.selector),
      abi.encode(0)
    );
    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(SwingTrader.sellMalt.selector, amount),
      abi.encode(actualAmount)
    );

    vm.prank(stabilizerNode);
    uint256 used = swingTraderManager.sellMalt(amount);

    assertEq(used, actualAmount);
    assertEq(actualAmount, amount / 2);
  }

  /* function testSellMaltMultipleTraders(uint256 amount) public { */
  /*   // TODO SwingTraderManager.t.sol  Mon 13 Feb 2023 17:49:21 GMT */
  /*   amount = bound(amount, 10000, 2**100); */

  /*   mintMalt(swingTrader, amount); */
  /*   mintMalt(rewardOverflow, amount); */

  /*   vm.mockCall( */
  /*     swingTrader, */
  /*     abi.encodeWithSelector(ISwingTrader.totalProfit.selector), */
  /*     abi.encode(0) */
  /*   ); */
  /*   vm.mockCall( */
  /*     rewardOverflow, */
  /*     abi.encodeWithSelector(ISwingTrader.totalProfit.selector), */
  /*     abi.encode(0) */
  /*   ); */
  /*   vm.mockCall( */
  /*     rewardOverflow, */
  /*     abi.encodeWithSelector(SwingTrader.sellMalt.selector, amount), */
  /*     abi.encode(amount) */
  /*   ); */

  /*   vm.prank(stabilizerNode); */
  /*   uint256 used = swingTraderManager.sellMalt(amount); */

  /*   assertEq(used, amount); */
  /* } */

  function testDelegateCapitalDoesNothingWithZeroBalance(address destination, uint256 amount) public {
    _setupContract();
    uint256 balance = rewardToken.balanceOf(destination);
    assertEq(balance, 0);

    vm.expectRevert("Must have capital delegation privs");
    swingTraderManager.delegateCapital(amount, destination);
    vm.prank(timelock);
    swingTraderManager.delegateCapital(amount, destination);

    balance = rewardToken.balanceOf(destination);
    assertEq(balance, 0);
  }

  function testDelegateCapitalDoesNothingWithZeroAmount(address destination) public {
    _setupContract();
    vm.assume(destination != address(0));
    uint256 balance = rewardToken.balanceOf(destination);
    assertEq(balance, 0);

    mintRewardToken(swingTrader, 10000 ether); // any amount > 0

    vm.expectRevert("Must have capital delegation privs");
    swingTraderManager.delegateCapital(0, destination);
    vm.prank(timelock);
    swingTraderManager.delegateCapital(0, destination);

    balance = rewardToken.balanceOf(destination);
    assertEq(balance, 0);
  }

  function testDelegateCapital(address destination, uint256 amount) public {
    _setupContract();
    vm.assume(destination != address(0));
    amount = bound(amount, 10000, 2**100);

    uint256 balance = rewardToken.balanceOf(destination);
    assertEq(balance, 0);

    mintRewardToken(swingTrader, amount);

    vm.expectRevert();
    swingTraderManager.delegateCapital(amount, destination);
    vm.mockCall(
      swingTrader,
      abi.encodeWithSelector(SwingTrader.delegateCapital.selector, amount),
      ""
    );
    vm.expectRevert();
    swingTraderManager.delegateCapital(amount, destination);
    vm.mockCall(
      rewardOverflow,
      abi.encodeWithSelector(SwingTrader.delegateCapital.selector, amount),
      ""
    );

    vm.prank(timelock);
    swingTraderManager.delegateCapital(amount, destination);
  }
}
