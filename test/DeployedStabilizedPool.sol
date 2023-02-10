import "./MaltTest.sol";
import "../../contracts/StabilizedPool/StabilizedPoolFactory.sol";
import "../../contracts/StabilizedPool/StabilizedPoolUpdater.sol";
import "../../contracts/GlobalImpliedCollateralService.sol";
import "../../contracts/Timekeeper.sol";
import "../../contracts/libraries/uniswap/IUniswapV2Router02.sol";
import "../../contracts/libraries/uniswap/IUniswapV2Factory.sol";
import "../../contracts/DataFeed/MovingAverage.sol";

contract DeployedStabilizedPool is MaltTest {
  using stdStorage for StdStorage;

  StabilizedPoolFactory poolFactory;
  StabilizedPoolUpdater poolUpdater;
  MaltTimekeeper timekeeper;
  GlobalImpliedCollateralService globalIC;
  IUniswapV2Router02 router;
  IUniswapV2Factory factory;
  IUniswapV2Pair lpToken;

  address keeperRegistry = nextAddress();
  address pool;
  address bondedUser = nextAddress();
  address dao = nextAddress();
  uint256 initialLpSupply;

  constructor() {
    globalIC = new GlobalImpliedCollateralService(
      address(repository),
      admin,
      address(malt),
      admin
    );

    timekeeper = new MaltTimekeeper(
      address(repository),
      60 * 120, // 2 hours
      block.timestamp,
      address(malt)
    );

    poolFactory = new StabilizedPoolFactory(
      address(repository),
      admin,
      address(malt),
      address(globalIC),
      address(transferService),
      address(timekeeper)
    );

    vm.startPrank(admin);
    globalIC.setUpdaterManager(address(poolFactory));
    transferService.setVerifierManager(address(poolFactory));

    address[] memory minters = new address[](1);
    minters[0] = address(timekeeper);
    address[] memory burners = new address[](0);
    malt.setupContracts(
      address(globalIC),
      address(poolFactory),
      minters,
      burners
    );

    address[] memory admins = new address[](1);
    admins[0] = admin;
    repository.setupContracts(
      timelock,
      admins,
      address(malt),
      address(timekeeper),
      address(transferService),
      address(globalIC),
      address(poolFactory)
    );

    StabilizedPool memory currentPool = deployContracts(address(poolFactory));

    lpToken = IUniswapV2Pair(
      factory.createPair(address(malt), address(rewardToken))
    );
    pool = address(lpToken);
    currentPool.pool = pool;
    vm.stopPrank();

    string memory name = "My Test Pool";

    poolUpdater = new StabilizedPoolUpdater(
      address(repository),
      address(poolFactory)
    );

    vm.startPrank(admin);
    poolFactory.initializeStabilizedPool(
      pool,
      name,
      address(rewardToken),
      address(poolUpdater)
    );

    poolFactory.setCurrentPool(pool, currentPool);

    poolFactory.setupUniv2StabilizedPool(pool);

    PoolTransferVerification verifier = PoolTransferVerification(
      currentPool.periphery.transferVerifier
    );
    verifier.togglePause();
    verifier.toggleKillswitch();
    IKeeperCompatibleInterface(currentPool.periphery.keeper).togglePaused();

    vm.stopPrank();

    initialLpSupply = bondUser(bondedUser, 300000 ether);
    vm.warp(block.timestamp + 30);
    upkeep();
    vm.warp(block.timestamp + 600);
    upkeep();
  }

  function deployContracts(address poolFactory)
    internal
    returns (StabilizedPool memory)
  {
    StabilizedPool memory currentPool;
    currentPool.collateralToken = address(rewardToken);
    currentPool.pool = pool;
    currentPool.updater = address(poolUpdater);
    string memory name = "My Test Pool";
    currentPool.name = name;

    {
      Auction auction = new Auction(
        timelock,
        address(repository),
        poolFactory,
        600,
        10**18
      );

      AuctionEscapeHatch auctionEscapeHatch = new AuctionEscapeHatch(
        timelock,
        address(repository),
        poolFactory
      );

      ImpliedCollateralService impliedCollateralService = new ImpliedCollateralService(
          timelock,
          address(repository),
          poolFactory
        );

      LiquidityExtension liquidityExtension = new LiquidityExtension(
        timelock,
        address(repository),
        poolFactory
      );

      ProfitDistributor profitDistributor = new ProfitDistributor(
        timelock,
        address(repository),
        poolFactory,
        dao,
        treasury
      );

      StabilizerNode stabilizerNode = new StabilizerNode(
        timelock,
        address(repository),
        poolFactory,
        10**20,
        10**20
      );

      SwingTrader swingTrader = new SwingTrader(
        timelock,
        address(repository),
        poolFactory
      );

      SwingTraderManager swingTraderManager = new SwingTraderManager(
        timelock,
        address(repository),
        poolFactory
      );

      currentPool.core.auction = address(auction);
      currentPool.core.auctionEscapeHatch = address(auctionEscapeHatch);
      currentPool.core.impliedCollateralService = address(
        impliedCollateralService
      );
      currentPool.core.liquidityExtension = address(liquidityExtension);
      currentPool.core.profitDistributor = address(profitDistributor);
      currentPool.core.stabilizerNode = address(stabilizerNode);
      currentPool.core.swingTrader = address(swingTrader);
      currentPool.core.swingTraderManager = address(swingTraderManager);
    }

    {
      Bonding bonding = new Bonding(
        timelock,
        address(repository),
        poolFactory,
        address(timekeeper)
      );

      MiningService miningService = new MiningService(
        timelock,
        address(repository),
        poolFactory
      );

      uint256 vestedPoolId = 0;
      uint256 linearPoolId = 1;

      ERC20VestedMine vestedMine = new ERC20VestedMine(
        timelock,
        address(repository),
        poolFactory,
        vestedPoolId
      );

      RewardMineBase linearMine = new RewardMineBase(
        timelock,
        address(repository),
        poolFactory,
        linearPoolId
      );

      ForfeitHandler forfeitHandler = new ForfeitHandler(
        timelock,
        address(repository),
        poolFactory,
        treasury
      );

      RewardReinvestor reinvestor = new RewardReinvestor(
        timelock,
        address(repository),
        poolFactory,
        treasury
      );

      currentPool.staking.bonding = address(bonding);
      currentPool.staking.miningService = address(miningService);
      currentPool.staking.vestedMine = address(vestedMine);
      currentPool.staking.forfeitHandler = address(forfeitHandler);
      currentPool.staking.linearMine = address(linearMine);
      currentPool.staking.reinvestor = address(reinvestor);
    }

    {
      VestingDistributor vestingDistributor = new VestingDistributor(
        timelock,
        admin,
        address(repository),
        poolFactory
      );

      LinearDistributor linearDistributor = new LinearDistributor(
        timelock,
        address(repository),
        poolFactory
      );

      RewardOverflowPool rewardOverflow = new RewardOverflowPool(
        timelock,
        address(repository),
        poolFactory
      );

      RewardThrottle rewardThrottle = new RewardThrottle(
        timelock,
        address(repository),
        poolFactory,
        address(timekeeper)
      );

      currentPool.rewardSystem.vestingDistributor = address(vestingDistributor);
      currentPool.rewardSystem.linearDistributor = address(linearDistributor);
      currentPool.rewardSystem.rewardOverflow = address(rewardOverflow);
      currentPool.rewardSystem.rewardThrottle = address(rewardThrottle);
    }

    {
      MaltDataLab maltDataLab = new MaltDataLab(
        timelock,
        address(repository),
        poolFactory
      );

      DualMovingAverage dualMA = new DualMovingAverage(
        address(repository),
        admin,
        30,
        60,
        (10**18) * 2,
        0,
        address(maltDataLab)
      );

      MovingAverage ratioMA = new MovingAverage(
        address(repository),
        admin,
        30 minutes, // sample length
        120, // sample memory - 2.5 days
        0,
        address(maltDataLab)
      );

      (router, factory) = _deployUniV2();

      IDexHandler dexHandler = new UniswapHandler(
        timelock,
        address(repository),
        poolFactory,
        address(router)
      );

      PoolTransferVerification transferVerifier = new PoolTransferVerification(
        timelock,
        address(repository),
        poolFactory,
        200,
        200,
        30,
        60 * 5
      );

      IKeeperCompatibleInterface keeper = new UniV2PoolKeeper(
        timelock,
        address(repository),
        poolFactory,
        keeperRegistry,
        address(timekeeper),
        treasury
      );

      currentPool.periphery.dataLab = address(maltDataLab);
      currentPool.periphery.dexHandler = address(dexHandler);
      currentPool.periphery.transferVerifier = address(transferVerifier);
      currentPool.periphery.keeper = address(keeper);
      currentPool.periphery.dualMA = address(dualMA);
      currentPool.periphery.swingTraderMaltRatioMA = address(ratioMA);
    }

    return currentPool;
  }

  function _deployUniV2()
    internal
    returns (IUniswapV2Router02 router, IUniswapV2Factory factory)
  {
    address wethAddress = deployBytecode(
      "contracts/libraries/uniswap/WETH9.bc"
    );
    bytes memory factoryArgs = abi.encode(address(0));
    address factoryAddress = deployBytecode(
      "contracts/libraries/uniswap/UniswapV2Factory.bc",
      factoryArgs
    );
    bytes memory routerArgs = abi.encode(factoryAddress, wethAddress);
    address routerAddress = deployBytecode(
      "contracts/libraries/uniswap/UniswapV2Router02.bc",
      routerArgs
    );
    router = IUniswapV2Router02(routerAddress);
    factory = IUniswapV2Factory(factoryAddress);
  }

  function assumeNoGlobalContracts(address _address) public {
    vm.assume(_address != address(malt));
    vm.assume(_address != address(rewardToken));
    vm.assume(_address != address(transferService));
    vm.assume(_address != address(timekeeper));
    vm.assume(_address != address(globalIC));
    vm.assume(_address != address(lpToken));
    vm.assume(_address != address(poolFactory));
    vm.assume(_address != keeperRegistry);
    vm.assume(_address != address(router));
    vm.assume(_address != pool);
    vm.assume(_address != timelock);
    vm.assume(_address != admin);
    vm.assume(_address != user);
    vm.assume(_address != treasury);
  }

  function assumeNoCoreContracts(address _address) public {
    (
      address auction,
      address auctionEscapeHatch,
      address impliedCollateralService,
      address liquidityExtension,
      address profitDistributor,
      address stabilizerNode,
      address swingTrader,
      address swingTraderManager
    ) = poolFactory.getCoreContracts(pool);

    vm.assume(_address != auction);
    vm.assume(_address != auctionEscapeHatch);
    vm.assume(_address != impliedCollateralService);
    vm.assume(_address != liquidityExtension);
    vm.assume(_address != profitDistributor);
    vm.assume(_address != stabilizerNode);
    vm.assume(_address != swingTrader);
    vm.assume(_address != swingTraderManager);
  }

  function assumeNoStakingContracts(address _address) public {
    (
      address bonding,
      address miningService,
      address vestedMine,
      address forfeitHandler,
      address linearMine,
      address reinvestor
    ) = poolFactory.getStakingContracts(pool);

    vm.assume(_address != bonding);
    vm.assume(_address != miningService);
    vm.assume(_address != vestedMine);
    vm.assume(_address != forfeitHandler);
    vm.assume(_address != linearMine);
    vm.assume(_address != reinvestor);
  }

  function assumeNoRewardSystemContracts(address _address) public {
    (
      address vestingDistributor,
      address linearDistributor,
      address rewardOverflow,
      address rewardThrottle
    ) = poolFactory.getRewardSystemContracts(pool);

    vm.assume(_address != vestingDistributor);
    vm.assume(_address != linearDistributor);
    vm.assume(_address != rewardOverflow);
    vm.assume(_address != rewardThrottle);
  }

  function assumeNoPeripheryContracts(address _address) public {
    (
      address dataLab,
      address dexHandler,
      address transferVerifier,
      address keeper,
      address dualMA
    ) = poolFactory.getPeripheryContracts(pool);

    vm.assume(_address != dataLab);
    vm.assume(_address != dexHandler);
    vm.assume(_address != transferVerifier);
    vm.assume(_address != keeper);
    vm.assume(_address != dualMA);
  }

  function assumeNoMaltContracts(address _address) public {
    vm.assume(_address != address(0));
    assumeNoGlobalContracts(_address);
    assumeNoCoreContracts(_address);
    assumeNoStakingContracts(_address);
    assumeNoRewardSystemContracts(_address);
  }

  function getCurrentStabilizedPool() public returns (StabilizedPool memory) {
    return poolFactory.getStabilizedPool(pool);
  }

  function deployBytecode(string memory path)
    public
    returns (address deployedAddress)
  {
    bytes memory bytecode = vm.readFileBinary(path);

    assembly {
      deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
    }
  }

  function deployBytecode(string memory path, bytes memory args)
    public
    returns (address deployedAddress)
  {
    bytes memory loadedBytecode = vm.readFileBinary(path);
    bytes memory bytecode = abi.encodePacked(loadedBytecode, args);

    assembly {
      deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
    }
  }

  function bondUser(address account, uint256 amount) public returns (uint256) {
    mintMalt(account, amount);
    mintRewardToken(account, amount);

    vm.startPrank(account);
    rewardToken.approve(address(router), amount);
    malt.approve(address(router), amount);

    (, , uint256 liquidityCreated) = router.addLiquidity(
      address(malt),
      address(rewardToken),
      amount,
      amount,
      0,
      0,
      account, // transfer LP tokens to sender
      block.timestamp
    );

    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    IBonding bonding = IBonding(currentPool.staking.bonding);

    lpToken.approve(address(bonding), amount);
    bonding.bond(0, liquidityCreated);

    vm.stopPrank();

    return liquidityCreated;
  }

  function upkeep() public {
    StabilizedPool memory currentPool = getCurrentStabilizedPool();

    IKeeperCompatibleInterface keeper = IKeeperCompatibleInterface(
      currentPool.periphery.keeper
    );

    (bool upkeepNeeded, bytes memory performData) = keeper.checkUpkeep(
      abi.encode("")
    );

    if (upkeepNeeded) {
      vm.prank(admin);
      keeper.performUpkeep(performData);
    }
  }
}
