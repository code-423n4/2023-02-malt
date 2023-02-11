# Malt contest details
- Total Prize Pool: $60,500 USDC
  - HM awards: $40,800 USDC 
  - QA report awards: $4,800 USDC 
  - Gas report awards: $2,400 USDC 
  - Judge + presort awards: $12,000 USDC
  - Scout awards: $500 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-02-malt-protocol-versus-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts February 14, 2023 20:00 UTC
- Ends February 20, 2023 20:00 UTC

## Automated Findings / Publicly Known Issues

Automated findings output for the contest can be found [here](add link to report) within an hour of contest opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

### Contact us
Discord handles to contact with questions about the protocol and their timezones:
* 0xScotch#6626 (GMT) (lead dev, ask anything)
* FelipeDlB#9359 (GMT-3) (non-technical but very knowledgeable about core mechanics)

[You are also welcome to join our discord](https://discord.gg/malt) (Let us know your handle and we will give you a special role for helping us out with security)

# Overview
## Index
* [High level overview of the Malt protocol](#high-level-overview-of-the-malt-protocol)
* [Testnet](#testnet)
* [Glossary Of Terms](#glossary-of-terms)
* [Contract Scope Overview](#scope)
* [Description of each contract in scope](#description-of-each-contract-in-scope)
* [Technical Notes](#technical-notes)
* [Known Issues / trade offs](#known-issues--trade-offs)

## High level overview of the Malt protocol

The goal of Malt is to maintain the price of the Malt token at $1 per Malt.

As Malt produces cashflow it will direct some of it towards a profit share with LPs. The rest of the capital produced will go towards collateralizing the protocol (by adding capital into the Swing Trader system).

But how does Malt produce cashflow and how can it ever become fully collateralized if it is sharing profit with LPs?

The protocol in it's current form can produce profit in two ways:
1. Minting fresh malt and selling it to collect the seignorage profit.
2. The Swing Trader system buying Malt at a discount below peg and selling it at or above peg.

Each of these methods produce profit. Part of which goes to LP profit share and the majority of which goes back into the Swing Trader system.

The secret sauce to Malt is that the protocol has the facility to buy back the stablecoin at or below its intrinsic value. This is not possible in more typical mint/redeem stablecoin designs. In those designs the collateral is static and only ever gets traded at its intrinsic value against the stablecoin.

The Malt Swing Trader can purchase Malt below its intrinsic value eg it may spend $0.9 on something it can afford to spend $1 to purchase. This $0.1 delta leaves more collateral relative to the supply it just removed. Thus improving the global collateral ratio for the remaining circulating supply.

There are other parts to the protocol such as the Dutch Auction for Arbitrage Tokens, but they are outside the scope of this audit.

The majority of the scope of this audit falls into two subsystems of the protocol:
1. The code determining the behaviour of the Swing Trader system ie price entry curves, triggering methods etc
2. The throttling of LP rewards (using a proportional control system) and the distribution of those rewards.

The remainder of the scope is taken up by helper contracts that store useful global state.

## Testnet
[Have a look at the protocol in action on the polygon mumbai testnet](https://testnet.malt.money)

## Glossary Of Terms

| Term                          | Definition                  |
| ----------------------------- | --------------------------- |
| Epoch                         | A 30 minute window used for APR accounting |
| Liquidity Extension           | A pool of capital used to facilitate offering a premium to participants in the Arbitrage Auctions  |
| Arbitrage Auction             | A dutch auction mechanism to raise capital to defend Malt's peg. An auction is used to allow price discovery on the premium for the risk of helping defend peg |
| Reserve Ratio                 | The ratio of capital in the Liquidity Extension pool vs the Malt in the AMM pool the Liquidity Extension is attached to |
| True Epoch APR                | The APR implied by total protocol profit in a given epoch against the average total value of bonded LP in that epoch |
| Desired Epoch APR             | The target APR the protocol is aiming for in a given epoch. The exact value of this is determined by a control system. |
| Implied Collateral            | The sum of capital sources that could be pulled upon to defend peg. Many of these sources are not purely serving the purpose of being collateral. Eg `RewardOverflowPool` is capital set aside to make up the difference in reward on epochs where desired APR isn't met. However, under peg some of this capital can be redirected to defend peg. More discussion on implied collateral below. |
| Swing Trader                  | This is a contract which privileged access whose role is to defend peg with capital and attempt to profit from Malt's price movements (thus increasing collateral over time). |
| Malt Data Lab                 | An internal oracle service that tracks moving averages of many useful internal streams of data (price, reserve ratio, AMM pool reserves etc) |
| Reward Throttle               | The contract that throttles an epoch's True APR to the Desired APR by either pushing or pulling capital to/from the `RewardOverflowPool` |
| Reward Overflow               | A pool of capital that is topped up when an epoch naturally reaches it's Desired APR. The overflow is depleted when an epoch fails to reach it's Desired APR. This pool can be thought of as a smoothing mechanism that takes excess profit from high activity epochs to subsidize APR in low activity epochs. |
| Reward Distributor            | The contract in charge of implementing the focal vesting scheme. It receives capital from the `RewardThrottle` and then vests it according to the focal scheme. A `vest` method can be called on this contract at any time and it will calculate how much reward has vested since the last call and send that capital to the `ERC20VestedMine` ready for user's to withdraw / reinvest it. |
| Focal Vesting                 | The scheme used to distribute rewards to bonded LPs. Rewards vest linearly towards the next "focal point". This means all rewards created in a certain period will vest towards the same point, making calculations significantly easier. The focal points are set by default such that the minimum vesting period is 24 hours and the maximum is 48hours (with a 24 hour catchment). More on this later. |

# Scope

The following is the scope broken down by the subsystems mentioned above. The purposes of each are listed in more detail below.

### Swing Trader
|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|Description and [Coverage](#nowhere "(Lines hit / Total)")|Libraries|
|:-|:-:|:-|:-|
|_Contracts (5)_|
|[contracts/DataFeed/MaltDataLab.sol#getSwingTraderEntryPrice](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DataFeed/MaltDataLab.sol#L350-L425)|[75](#nowhere "(nSLOC:35, SLOC:75, Lines:75)")|-| `@openzeppelin/*`|
|[contracts/DataFeed/MaltDataLab.sol#getActualPriceTarget](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DataFeed/MaltDataLab.sol#L427-L478)|[51](#nowhere "(nSLOC:36, SLOC:51, Lines:51)")|-| `@openzeppelin/*`|
|[contracts/DataFeed/MaltDataLab.sol#getRealBurnBudget](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DataFeed/MaltDataLab.sol#L230-L258)|[28](#nowhere "(nSLOC:15, SLOC:28, Lines:28)")|-| `@openzeppelin/*`|
|[contracts/Token/Malt.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Token/Malt.sol)|[180](#nowhere "(nSLOC:141, SLOC:180, Lines:230)")|-||
|[contracts/Token/TransferService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Token/TransferService.sol)|[161](#nowhere "(nSLOC:131, SLOC:161, Lines:209)")|-| `@openzeppelin/*`|
|[contracts/StabilityPod/SwingTraderManager.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/SwingTraderManager.sol) [♻️](#nowhere "TryCatch Blocks")|[369](#nowhere "(nSLOC:325, SLOC:369, Lines:465)")|-| `@openzeppelin/*`|
|[contracts/StabilityPod/StabilizerNode.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/StabilizerNode.sol)|[544](#nowhere "(nSLOC:445, SLOC:544, Lines:679)")|-| `@openzeppelin/*`|
|Total (over 5 files):| [1408](#nowhere "(nSLOC:1128, SLOC:1408, Lines:1408)") |-|

### Reward Throttling + Distribution
|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|Description and [Coverage](#nowhere "(Lines hit / Total)")|Libraries|
|:-|:-:|:-|:-|
|_Contracts (2)_|
|[contracts/RewardSystem/RewardThrottle.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/RewardThrottle.sol)|[579](#nowhere "(nSLOC:493, SLOC:579, Lines:768)")|-| `@openzeppelin/*`|
|[contracts/RewardSystem/LinearDistributor.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/LinearDistributor.sol)|[178](#nowhere "(nSLOC:152, SLOC:178, Lines:240)")|-| `@openzeppelin/*`|
|Total (over 2 files):| [757](#nowhere "(nSLOC:645, SLOC:757, Lines:1008)") |-|

### Global state + helpers
|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|Description and [Coverage](#nowhere "(Lines hit / Total)")|Libraries|
|:-|:-:|:-|:-|
|_Contracts (4)_|
|[contracts/StabilityPod/ImpliedCollateralService.sol#getCollateralizedMalt](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/ImpliedCollateralService.sol#L94-L132)|[34](#nowhere "(nSLOC:34, SLOC:38, Lines:38)")|-| `@openzeppelin/*`|
|[contracts/DataFeed/MaltDataLab.sol#rewardToMaltDecimals](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DataFeed/MaltDataLab.sol#L279-L292)|[13](#nowhere "(nSLOC:13, SLOC:13, Lines:13)")|-| `@openzeppelin/*`|
|[contracts/DataFeed/MaltDataLab.sol#maltToRewardDecimals](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DataFeed/MaltDataLab.sol#L260-L277)|[17](#nowhere "(nSLOC:17, SLOC:17, Lines:17)")|-| `@openzeppelin/*`|
|[contracts/GlobalImpliedCollateralService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/GlobalImpliedCollateralService.sol)|[189](#nowhere "(nSLOC:183, SLOC:189, Lines:245)")|-| `@openzeppelin/*`|
|[contracts/Repository.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Repository.sol) [🧮](#nowhere "Uses Hash-Functions")|[196](#nowhere "(nSLOC:150, SLOC:196, Lines:242)")|-| `@openzeppelin/*`|
|Total (over 4 files):| [452](#nowhere "(nSLOC:449, SLOC:452, Lines:452)") |-|

**Total sloc = 2617**

*All lines of code were counted using `cloc` tool on linux. Only lines of code are counted, not blanks / comments etc*

## Out of scope

|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|Description and [Coverage](#nowhere "(Lines hit / Total)")|Libraries|
|:-|:-:|:-|:-|
|_Contracts (28)_|
|[contracts/Testnet/MintableERC20.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Testnet/MintableERC20.sol)|[10](#nowhere "(nSLOC:10, SLOC:10, Lines:14)")|-| `@openzeppelin/*`|
|[contracts/Testnet/Faucet.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Testnet/Faucet.sol)|[12](#nowhere "(nSLOC:12, SLOC:12, Lines:17)")|-| `@openzeppelin/*`|
|[contracts/Testnet/Multicall.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Testnet/Multicall.sol)|[50](#nowhere "(nSLOC:39, SLOC:50, Lines:66)")|-||
|[contracts/Testnet/MaltFaucet.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Testnet/MaltFaucet.sol) [📤](#nowhere "Initiates ETH Value Transfer")|[57](#nowhere "(nSLOC:57, SLOC:57, Lines:76)")|-||
|[contracts/Timekeeper.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Timekeeper.sol) [🧪](#nowhere "Experimental Features") [💰](#nowhere "Payable Functions")|[65](#nowhere "(nSLOC:59, SLOC:65, Lines:90)")|-| `@openzeppelin/*`|
|[contracts/Staking/ForfeitHandler.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Staking/ForfeitHandler.sol)|[69](#nowhere "(nSLOC:59, SLOC:69, Lines:101)")|-| `@openzeppelin/*`|
|[contracts/RewardSystem/RewardOverflowPool.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/RewardOverflowPool.sol)|[85](#nowhere "(nSLOC:65, SLOC:85, Lines:117)")|-| `@openzeppelin/*`|
|[contracts/Permissions.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Permissions.sol)|[101](#nowhere "(nSLOC:76, SLOC:101, Lines:130)")|-| `@openzeppelin/*`|
|[contracts/Staking/RewardMineBase.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Staking/RewardMineBase.sol)|[113](#nowhere "(nSLOC:88, SLOC:113, Lines:154)")|-| `@openzeppelin/*`|
|[contracts/Token/ERC20Permit.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Token/ERC20Permit.sol) [🧮](#nowhere "Uses Hash-Functions") [🔖](#nowhere "Handles Signatures: ecrecover")|[141](#nowhere "(nSLOC:97, SLOC:141, Lines:177)")|-| `@openzeppelin/*`|
|[contracts/Staking/RewardReinvestor.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Staking/RewardReinvestor.sol)|[152](#nowhere "(nSLOC:116, SLOC:152, Lines:197)")|-| `@openzeppelin/*`|
|[contracts/StabilityPod/LiquidityExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/LiquidityExtension.sol)|[162](#nowhere "(nSLOC:125, SLOC:162, Lines:211)")|-| `@openzeppelin/*`|
|[contracts/Timelock.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Timelock.sol) [🖥](#nowhere "Uses Assembly") [💰](#nowhere "Payable Functions") [🧮](#nowhere "Uses Hash-Functions")|[178](#nowhere "(nSLOC:136, SLOC:178, Lines:228)")|-||
|[contracts/Staking/MiningService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Staking/MiningService.sol)|[185](#nowhere "(nSLOC:131, SLOC:185, Lines:237)")|-| `@openzeppelin/*`|
|[contracts/Token/PoolTransferVerification.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Token/PoolTransferVerification.sol)|[208](#nowhere "(nSLOC:153, SLOC:208, Lines:248)")|-||
|[contracts/StabilityPod/SwingTrader.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/SwingTrader.sol)|[213](#nowhere "(nSLOC:167, SLOC:213, Lines:271)")|-| `@openzeppelin/*`|
|[contracts/Auction/AuctionEscapeHatch.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Auction/AuctionEscapeHatch.sol)|[244](#nowhere "(nSLOC:185, SLOC:244, Lines:312)")|-| `@openzeppelin/*`|
|[contracts/StabilityPod/ProfitDistributor.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/ProfitDistributor.sol)|[263](#nowhere "(nSLOC:217, SLOC:263, Lines:356)")|-| `@openzeppelin/*`|
|[contracts/Staking/ERC20VestedMine.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Staking/ERC20VestedMine.sol)|[277](#nowhere "(nSLOC:222, SLOC:277, Lines:414)")|-| `@openzeppelin/*`|
|[contracts/DataFeed/MovingAverage.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DataFeed/MovingAverage.sol)|[293](#nowhere "(nSLOC:247, SLOC:293, Lines:411)")|-||
|[contracts/RewardSystem/VestingDistributor.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/VestingDistributor.sol)|[325](#nowhere "(nSLOC:276, SLOC:325, Lines:440)")|-| `@openzeppelin/*`|
|[contracts/ops/UniV2PoolKeeper.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/ops/UniV2PoolKeeper.sol) [♻️](#nowhere "TryCatch Blocks")|[335](#nowhere "(nSLOC:272, SLOC:335, Lines:397)")|-| `@openzeppelin/*`|
|[contracts/DataFeed/DualMovingAverage.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DataFeed/DualMovingAverage.sol)|[367](#nowhere "(nSLOC:314, SLOC:367, Lines:488)")|-||
|[contracts/DexHandlers/UniswapHandler.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DexHandlers/UniswapHandler.sol)|[396](#nowhere "(nSLOC:297, SLOC:396, Lines:499)")|-| `@openzeppelin/*`|
|[contracts/StabilizedPool/StabilizedPoolUpdater.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPool/StabilizedPoolUpdater.sol)|[495](#nowhere "(nSLOC:415, SLOC:495, Lines:583)")|-||
|[contracts/Staking/Bonding.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Staking/Bonding.sol) [🧮](#nowhere "Uses Hash-Functions")|[523](#nowhere "(nSLOC:425, SLOC:523, Lines:671)")|-| `@openzeppelin/*`|
|[contracts/StabilizedPool/StabilizedPoolFactory.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPool/StabilizedPoolFactory.sol)|[531](#nowhere "(nSLOC:453, SLOC:531, Lines:586)")|-||
|[contracts/Auction/Auction.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Auction/Auction.sol)|[980](#nowhere "(nSLOC:772, SLOC:980, Lines:1240)")|-| `@openzeppelin/*`|
|_Abstracts (18)_|
|[contracts/StabilizedPoolExtensions/AuctionExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/AuctionExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/BondingExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/BondingExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/DataLabExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/DataLabExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/DexHandlerExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/DexHandlerExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/GlobalICExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/GlobalICExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/MiningServiceExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/MiningServiceExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/RewardOverflowExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/RewardOverflowExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/RewardThrottleExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/RewardThrottleExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/StabilizerNodeExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/StabilizerNodeExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/SwingTraderExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/SwingTraderExtension.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:29)")|-||
|[contracts/StabilizedPoolExtensions/LiquidityExtensionExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/LiquidityExtensionExtension.sol)|[18](#nowhere "(nSLOC:15, SLOC:18, Lines:32)")|-||
|[contracts/StabilizedPoolExtensions/ProfitDistributorExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/ProfitDistributorExtension.sol)|[18](#nowhere "(nSLOC:15, SLOC:18, Lines:32)")|-||
|[contracts/StabilizedPoolExtensions/SwingTraderManagerExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/SwingTraderManagerExtension.sol)|[18](#nowhere "(nSLOC:15, SLOC:18, Lines:32)")|-||
|[contracts/StabilizedPoolExtensions/ImpliedCollateralServiceExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/ImpliedCollateralServiceExtension.sol)|[22](#nowhere "(nSLOC:17, SLOC:22, Lines:36)")|-||
|[contracts/Token/AbstractTransferVerification.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Token/AbstractTransferVerification.sol)|[25](#nowhere "(nSLOC:12, SLOC:25, Lines:32)")|-||
|[contracts/StabilizedPoolExtensions/StabilizedPoolUnit.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPoolExtensions/StabilizedPoolUnit.sol)|[74](#nowhere "(nSLOC:71, SLOC:74, Lines:93)")|-||
|[contracts/Auction/AuctionParticipant.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Auction/AuctionParticipant.sol)|[142](#nowhere "(nSLOC:126, SLOC:142, Lines:199)")|-| `@openzeppelin/*`|
|[contracts/Staking/AbstractRewardMine.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Staking/AbstractRewardMine.sol)|[274](#nowhere "(nSLOC:214, SLOC:274, Lines:391)")|-| `@openzeppelin/*`|
|_Libraries (8)_|
|[contracts/libraries/uniswap/UniswapV2OracleLibrary.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/UniswapV2OracleLibrary.sol)|[36](#nowhere "(nSLOC:28, SLOC:36, Lines:50)")|-||
|[contracts/libraries/uniswap/Babylonian.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/Babylonian.sol)|[44](#nowhere "(nSLOC:44, SLOC:44, Lines:52)")|-||
|[contracts/libraries/uniswap/FullMath.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/FullMath.sol) [🖥](#nowhere "Uses Assembly")|[65](#nowhere "(nSLOC:57, SLOC:65, Lines:134)")|-||
|[contracts/libraries/uniswap/BitMath.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/BitMath.sol)|[75](#nowhere "(nSLOC:75, SLOC:75, Lines:85)")|-||
|[contracts/libraries/SafeBurnMintableERC20.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/SafeBurnMintableERC20.sol)|[82](#nowhere "(nSLOC:56, SLOC:82, Lines:124)")|-| `@openzeppelin/*`|
|[contracts/libraries/UniswapV2Library.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/UniswapV2Library.sol) [🧮](#nowhere "Uses Hash-Functions")|[124](#nowhere "(nSLOC:92, SLOC:124, Lines:144)")|-| `@openzeppelin/*`|
|[contracts/libraries/uniswap/FixedPoint.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/FixedPoint.sol)|[140](#nowhere "(nSLOC:112, SLOC:140, Lines:191)")|-||
|[contracts/libraries/ABDKMath64x64.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/ABDKMath64x64.sol) [Σ](#nowhere "Unchecked Blocks")|[565](#nowhere "(nSLOC:565, SLOC:565, Lines:839)")|-||
|_Interfaces (36)_|
|[contracts/interfaces/IAuctionStartController.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IAuctionStartController.sol)|[4](#nowhere "(nSLOC:4, SLOC:4, Lines:6)")|-||
|[contracts/interfaces/IForfeit.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IForfeit.sol)|[4](#nowhere "(nSLOC:4, SLOC:4, Lines:6)")|-||
|[contracts/interfaces/IProfitDistributor.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IProfitDistributor.sol)|[4](#nowhere "(nSLOC:4, SLOC:4, Lines:6)")|-||
|[contracts/interfaces/IRepository.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IRepository.sol)|[4](#nowhere "(nSLOC:4, SLOC:4, Lines:6)")|-||
|[contracts/interfaces/IStabilizedPoolUpdater.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IStabilizedPoolUpdater.sol)|[4](#nowhere "(nSLOC:4, SLOC:4, Lines:6)")|-||
|[contracts/interfaces/ISupplyDistributionController.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/ISupplyDistributionController.sol)|[4](#nowhere "(nSLOC:4, SLOC:4, Lines:6)")|-||
|[contracts/interfaces/ITimekeeper.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/ITimekeeper.sol)|[9](#nowhere "(nSLOC:9, SLOC:9, Lines:16)")|-||
|[contracts/interfaces/IOverflow.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IOverflow.sol)|[11](#nowhere "(nSLOC:7, SLOC:11, Lines:16)")|-||
|[contracts/interfaces/IStabilizerNode.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IStabilizerNode.sol)|[11](#nowhere "(nSLOC:11, SLOC:11, Lines:20)")|-||
|[contracts/interfaces/IImpliedCollateralService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IImpliedCollateralService.sol)|[12](#nowhere "(nSLOC:9, SLOC:12, Lines:19)")|-||
|[contracts/interfaces/IBondExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IBondExtension.sol)|[13](#nowhere "(nSLOC:5, SLOC:13, Lines:16)")|-||
|[contracts/interfaces/ILiquidityExtension.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/ILiquidityExtension.sol)|[13](#nowhere "(nSLOC:10, SLOC:13, Lines:21)")|-||
|[contracts/interfaces/IERC20Permit.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IERC20Permit.sol)|[14](#nowhere "(nSLOC:6, SLOC:14, Lines:58)")|-||
|[contracts/interfaces/IDistributor.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IDistributor.sol)|[15](#nowhere "(nSLOC:15, SLOC:15, Lines:26)")|-||
|[contracts/interfaces/ITransferVerification.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/ITransferVerification.sol)|[16](#nowhere "(nSLOC:4, SLOC:16, Lines:18)")|-||
|[contracts/interfaces/IGlobalImpliedCollateralService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IGlobalImpliedCollateralService.sol)|[17](#nowhere "(nSLOC:17, SLOC:17, Lines:32)")|-||
|[contracts/interfaces/ISwingTrader.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/ISwingTrader.sol)|[17](#nowhere "(nSLOC:11, SLOC:17, Lines:26)")|-||
|[contracts/interfaces/IRewardThrottle.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IRewardThrottle.sol)|[18](#nowhere "(nSLOC:10, SLOC:18, Lines:26)")|-||
|[contracts/interfaces/IKeeperCompatibleInterface.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IKeeperCompatibleInterface.sol)|[19](#nowhere "(nSLOC:8, SLOC:19, Lines:24)")|-||
|[contracts/interfaces/IMovingAverage.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IMovingAverage.sol)|[19](#nowhere "(nSLOC:8, SLOC:19, Lines:25)")|-||
|[contracts/interfaces/IBurnMintableERC20.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IBurnMintableERC20.sol)|[21](#nowhere "(nSLOC:14, SLOC:21, Lines:89)")|-||
|[contracts/interfaces/IDualMovingAverage.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IDualMovingAverage.sol)|[21](#nowhere "(nSLOC:7, SLOC:21, Lines:26)")|-||
|[contracts/libraries/uniswap/IERC20.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/IERC20.sol)|[21](#nowhere "(nSLOC:14, SLOC:21, Lines:32)")|-||
|[contracts/libraries/uniswap/IUniswapV2Factory.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/IUniswapV2Factory.sol)|[22](#nowhere "(nSLOC:17, SLOC:22, Lines:32)")|-||
|[contracts/interfaces/IMalt.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IMalt.sol)|[25](#nowhere "(nSLOC:18, SLOC:25, Lines:40)")|-||
|[contracts/interfaces/ITransferService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/ITransferService.sol)|[26](#nowhere "(nSLOC:10, SLOC:26, Lines:34)")|-||
|[contracts/interfaces/IMiningService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IMiningService.sol)|[27](#nowhere "(nSLOC:9, SLOC:27, Lines:34)")|-||
|[contracts/interfaces/IRewardMine.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IRewardMine.sol)|[32](#nowhere "(nSLOC:22, SLOC:32, Lines:52)")|-||
|[contracts/interfaces/IBonding.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IBonding.sol)|[33](#nowhere "(nSLOC:15, SLOC:33, Lines:46)")|-||
|[contracts/libraries/uniswap/IUniswapV2Router02.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/IUniswapV2Router02.sol) [💰](#nowhere "Payable Functions")|[44](#nowhere "(nSLOC:9, SLOC:44, Lines:51)")|-||
|[contracts/interfaces/IMaltDataLab.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IMaltDataLab.sol)|[55](#nowhere "(nSLOC:31, SLOC:55, Lines:83)")|-||
|[contracts/interfaces/IDexHandler.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IDexHandler.sol)|[58](#nowhere "(nSLOC:21, SLOC:58, Lines:77)")|-||
|[contracts/interfaces/IStabilizedPoolFactory.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IStabilizedPoolFactory.sol)|[60](#nowhere "(nSLOC:11, SLOC:60, Lines:69)")|-||
|[contracts/libraries/uniswap/IUniswapV2Pair.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/IUniswapV2Pair.sol)|[75](#nowhere "(nSLOC:48, SLOC:75, Lines:105)")|-||
|[contracts/interfaces/IAuction.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/interfaces/IAuction.sol)|[120](#nowhere "(nSLOC:30, SLOC:120, Lines:148)")|-||
|[contracts/libraries/uniswap/IUniswapV2Router01.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/libraries/uniswap/IUniswapV2Router01.sol) [💰](#nowhere "Payable Functions")|[141](#nowhere "(nSLOC:22, SLOC:141, Lines:161)")|-||
|_Structs (2)_|
|[contracts/StabilityPod/PoolCollateral.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/PoolCollateral.sol)|[18](#nowhere "(nSLOC:18, SLOC:18, Lines:21)")|-||
|[contracts/StabilizedPool/StabilizedPool.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilizedPool/StabilizedPool.sol)|[43](#nowhere "(nSLOC:43, SLOC:43, Lines:49)")|-||
|Total (over 92 files):| [9772](#nowhere "(nSLOC:7662, SLOC:9772, Lines:13015)") |-|

## External imports
* **openzeppelin/access/AccessControl.sol**
  * [contracts/Repository.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Repository.sol)
* **openzeppelin/security/Pausable.sol**
  * [contracts/StabilityPod/StabilizerNode.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/StabilizerNode.sol)
* **openzeppelin/token/ERC20/ERC20.sol**
  * [contracts/DataFeed/MaltDataLab.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/DataFeed/MaltDataLab.sol)
  * [contracts/GlobalImpliedCollateralService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/GlobalImpliedCollateralService.sol)
  * [contracts/Repository.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Repository.sol)
  * [contracts/RewardSystem/LinearDistributor.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/LinearDistributor.sol)
  * [contracts/RewardSystem/RewardThrottle.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/RewardThrottle.sol)
  * [contracts/StabilityPod/ImpliedCollateralService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/ImpliedCollateralService.sol)
  * [contracts/StabilityPod/StabilizerNode.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/StabilizerNode.sol)
  * [contracts/StabilityPod/SwingTraderManager.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/SwingTraderManager.sol)
* **openzeppelin/token/ERC20/utils/SafeERC20.sol**
  * [contracts/Repository.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Repository.sol)
  * [contracts/RewardSystem/LinearDistributor.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/LinearDistributor.sol)
  * [contracts/RewardSystem/RewardThrottle.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/RewardThrottle.sol)
  * [contracts/StabilityPod/ImpliedCollateralService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/ImpliedCollateralService.sol)
  * [contracts/StabilityPod/StabilizerNode.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/StabilizerNode.sol)
  * [contracts/StabilityPod/SwingTraderManager.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/StabilityPod/SwingTraderManager.sol)
* **openzeppelin/utils/math/Math.sol**
  * [contracts/RewardSystem/RewardThrottle.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/RewardSystem/RewardThrottle.sol)
* **openzeppelin/utils/structs/EnumerableSet.sol**
  * [contracts/Token/TransferService.sol](https://github.com/code-423n4/2023-02-malt/blob/main/contracts/Token/TransferService.sol)


## Description of each contract in scope

Much of the Malt system remains unchanged from the previous audit. So the [description of the protocol](https://github.com/code-423n4/2021-11-malt) in that repo will still apply.

These are the only significant changes to what is described in that README:
1. The dutch auction now triggers before the swing trader, not after
2. The internal auctions have been completely removed. Instead all internal movement of capital happens through the swing trader or liquidity extension now.

Here is a breakdown of the contracts that are new / have changed since then and are thus in scope.

### ImpliedCollateralService#getCollateralizedMalt
This method aggregates collateral information from the current pool and returns a `PoolCollateral` struct. The idea here for this method to call `sync` on the `GlobalImpliedCollateral` so we can keep track of global metrics, not just per pool.

### MaltDataLab#getSwingTraderEntryPrice
This implements a curve that dictates at what price the swing trader will begin buying back Malt. The curve itself is a function of three things:
1. The ratio of Malt to total capital held by the protocol.
2. The current global collateral ratio.
3. An internal parameter to set the point at which the swing trader will only ever buy below the intrinsic value of Malt.

[This desmos graph implements the equations](https://www.desmos.com/calculator/nilxvwurmo)

There will also be a video describing this behaviour linked below in the additional context section.

### MaltDataLab#getActualPriceTarget
This is related to the above curve in that it dictates what price the swing trader will aim to return the AMM to when it purchases. The default behaviour is to return price back to the $1 peg. However, as internal parameters of the Swing Trader chance (namely, the ratio of Malt to the total capital it holds) the target price will start to drop from $1 towards the current intrinsic value of the collateral. Of course, if we are above 100% collateral then this should always return $1.

This curve is also a function of the same inputs as the `getSwingTraderEntryPrice` curve above. The desmos graph above also implements this curve and the below video will also talk through it further.

### MaltDataLab#getRealBurnBudget
This method is a bit of an outlier in that it is actually for the auction system which is not in scope other than this method. However, the method itself requires no deep understanding of the auction system. 

The method is given 2 arguments: `maxBurn` and `premiumExcess` and it must return a value between those two.

It should never return anything more than `maxBurn` and never lower than `premiumExcess` except in the exact case that `maxBurn` itself is a value below `premiumExcess` in which case `maxBurn` should be returned.

### MaltDataLab#rewardToMaltDecimals and MaltDataLab#maltToRewardDecimals
These are both helpers methods to convert between the decimal representations of Malt (18 decimals) and whatever other token it is paired with in the current pool.

These methods are largely redundant for the initial iteration of the protocol as we will be launching with a single DAI pool, which also uses 18 decimals. We added these methods to future proof the code for when we do deploy these contracts for pools that use non 18 decimal tokens.

### Malt
The actual ERC20 token for the protocol. It is a regular ERC20 with the following additions:
1. There is an access control for a Monetary Manager contract that has the power (via a timelock) to add and remove minters/burners for the token.
2. Approved minters and burners can mint and burn.
3. Handover (propose, accept) of the monetary manager.
4. `_beforeTokenTransfer` calls `TransferService` which has logic to block Malt purchasing on specific AMM pools under certain conditions. 
5. `totalSupply` subtracts off any Malt held by the Swing Trader system as this Malt is functionally burned. The only way it returns into circulation is to be sold to stabilize when price is above peg.

### TransferService
Contract that does the logic to dispatch requests to validate if a particular Malt transfer is allowed.

This contract was part of the previous c4 audit we had done but since then we have added the verifier manager role and the propose accept flow to update the manager. This is the core of what we want checked on this contract.

### RewardThrottle
As the protocol produces profit, the portion that is allocated to LPs gets sent to this contract. The job of this contract is to throttle the amount of capital coming through it to control the APR the users receive. Any additional capital above the desired APR is sent to the `RewardOverflow` contract. If at any epoch the throttle contract doesn't have enough capital it will pull in capital from the overflow to keep the APR smoothed.

The throttled desired APR is dictated by a proportional control system. The flow works something like this:

1. We seed the desired APR at some value to start.
2. Based on the current value of staked LP calculate how much cashflow is required to reach the desired APR for this epoch.
3. If a given epoch reaches that desired APR all additional cashflow from that epoch will go to the overflow.
4. The contract still keeps track of the "real" cashflow in the epoch, regardless of how much gets sent to overflow.
5. If the moving average of the real cashflow is above 2x the required cashflow for the desired APR, then the control system will increase the desired APR slightly. If the real cashflow is below the requirement then it lowers the desired APR.

In this way the throttling system smooths out the cashflow being sent to users in a conservative and sustainable manner using a control system that will dynamically find the equilibrium point for cashflow to remain sustainable.

### StabilizerNode
This is the core "dispatcher" contract of the entire stabilization system. The `stabilize` method on this contract is the externally callable method that will trigger the protocol to take some action to stabilize the price of Malt by minting Malt, triggering and auction or triggering the swing trader.

### LinearDistributor
The core rewards system that was audited previous involves a vesting period on rewards. This is still the case. However, the vesting system introduces a lot of complexity that limits composability with outside systems such as autocompounding farms. This linear distributor contract is meant to run alongside the vesting distributor and match the APR paid by that vesting contract.

Then the autocompounders can use the linear distributor contract instead and recover the composability while still maintaining the internal benefits of the vesting system.

### SwingTraderManager
Each pool has two contracts that have Swing Trader capabilities: The swing trader itself as well as the reward overflow. This SwingTraderManager contract abstracts them away from the consumer so they can just call methods on the manager contract and it will figure out how to route those requests to the underlying swing trader capable contracts.

It can also return high level metrics of the aggregate of the underlying contracts.

### GlobalImpliedCollateralService
This contract aggregates collateral data across all pools in the entire protocol. Each deployed pool has its own local `ImpliedCollateralService` that keeps track of metrics specific to that pool. That local contract can then relay that data back to the `GlobalImpliedCollateralService` which then aggregates that data across the entire protocol.

### Repository
The core reason for introducing this contract is due to the nature of managing access permissions at scale. The Malt system needs to deploy a suite of contracts per pool we support. Managing access permissions across all of those will get unweildy and error prone very quickly.

To solve this problem a 2 tier permissioning system was introduced. Each contract inherits `Permissions` which gives it the ability to control local access on a per contract basis. However, that `Permission` now will also make a call back to this `Repository` to check if the current `msg.sender` has a particular permission globally.

This allows us to give granular per contract permissions as well as granting broader roles on a global level.

An example anticipated use case for this will be create a sub dao that controls protocol parameters across all pools. Instead of needing to grant that dao specific permissions across all pools, they can be granted the permission globally in a single call.

## Technical Notes
Pretty much everything mentioned in the README of [our first C4 audit](https://github.com/code-423n4/2021-11-malt) is still valid.

These are the only significant changes to what is described in that README:
1. The dutch auction now triggers before the swing trader, not after
2. The internal auctions have been completely removed. Instead all internal movement of capital happens through the swing trader or liquidity extension now.

## Known Issues / trade offs
- There are some places in the codebase where decimals are assumed to be 18. The initial pool will only be against DAI which is 18 decimals.

# Additional Context

### Swing Trader Entry Price Curve
![Swing Trader Entry Price](https://cdn.discordapp.com/attachments/870710788896206898/1004150900396404827/stEntryEquations.PNG)

This is a curve that is meant to decay towards the current implied collateral %.
- `C_ic` the current implied collateral %.
- `z` is the point at which the curve will intersect the IC%.
- `S_b` is the price the curve will asymptotically approach (some value below IC%).
- `maltRatio` is the ratio of Malt to total capital held in the swing trader.

### Swing Trader Target Price Curve
![Swing Trader Target Price](https://cdn.discordapp.com/attachments/843616558182170645/1005199523360026675/unknown.png)

`z` and `C_ic` in this equation are the same as above. The new variable `d` is the value of the Malt ratio in the swing trader in which the target price will break from $1 and start to decend linear towards the IC%.

Find the desmos graph implementing these curves [here](https://www.desmos.com/calculator/nilxvwurmo)
The video walking through the desmos graph [here](https://drive.google.com/file/d/1R18oZGjIcsJaWNbBVod5aNjvK_LKNJO-/view?usp=sharing)

## Scoping Details 
```
- If you have a public code repo, please share it here:  Not public yet. But its an extension / improvement upon the previous audit (https://docs.malt.money/)
- How many contracts are in scope?:   10
- Total SLoC for these contracts?:  2626
- How many external imports are there?:  2
- How many separate interfaces and struct definitions are there for the contracts within scope?:  10
- Does most of your code generally use composition or inheritance?:   composition
- How many external calls?:   1
- What is the overall line coverage percentage provided by your tests?:  50
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?:   false
- Please describe required context:  
- Does it use an oracle?:  false
- Does the token conform to the ERC20 standard?:  yes
- Are there any novel or unique curve logic or mathematical models?: We have an exponential decay curve that defines the entry price for the token buyback using collateral. That curve moves between $1 and decays exponentially to just below intrinsic backing as a function of the amount of malt vs collateral held in the buyback contract
- Does it use a timelock function?:  no
- Is it an NFT?: no
- Does it have an AMM?: false  
- Is it a fork of a popular project?:   false
- Does it use rollups?:   false
- Is it multi-chain?:  false
- Does it use a side-chain?: false
```

# Tests

- Copy `.env.example` into `.env` and fill in the keys.
- `forge install`
- `forge test`
