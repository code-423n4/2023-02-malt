# Malt contest details
- Total Prize Pool: $60,500 USDC
  - HM awards: $40,800 USDC 
  - QA report awards: $4,800 USDC 
  - Gas report awards: $2,400 USDC 
  - Judge + presort awards: $12,000 USDC
  - Scout awards: $500 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-02-malt-contest/submit)
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
| Contract / Method                                                       | SLOC        | 
| ---------------------------------------------------------------------- | ------------ |
| [`DataFeed/MaltDataLab.sol#getSwingTraderEntryPrice`](https://github.com/code-423n4/2023-02-malt/contracts/DataFeed/MaltDataLab.sol)                | 75           |
| [`DataFeed/MaltDataLab.sol#getActualPriceTarget`](https://github.com/code-423n4/2023-02-malt/contracts/DataFeed/MaltDataLab.sol)                    | 51           |
| [`DataFeed/MaltDataLab.sol#getRealBurnBudget`](https://github.com/code-423n4/2023-02-malt/contracts/DataFeed/MaltDataLab.sol)                       | 28           |
| [`Token/Malt.sol`](https://github.com/code-423n4/2023-02-malt/contracts/Token/Malt.sol)                                                   | 180          |
| [`Token/TransferService.sol.sol`](https://github.com/code-423n4/2023-02-malt/contracts/Token/TransferService.sol)                                    | 161          |
| [`StabilityPod/SwingTraderManager.sol`](https://github.com/code-423n4/2023-02-malt/contracts/StabilityPod/SwingTraderManager.sol)                              | 381          |
| [`StabilityPod/StabilizerNode.sol`](https://github.com/code-423n4/2023-02-malt/contracts/StabilityPod/StabilizerNode.sol)                                  | 544          |
| **Total**                                                              | **1420**     |

### Reward Throttling + Distribution
| Contract / Method                                                       | SLOC        |
| ---------------------------------------------------------------------- | ------------ |
| [`RewardSystem/RewardThrottle.sol`](https://github.com/code-423n4/2023-02-malt/contracts/RewardSystem/RewardThrottle.sol)                                  | 579          |
| [`RewardSystem/LinearDistributor.sol`](https://github.com/code-423n4/2023-02-malt/contracts/RewardSystem/LinearDistributor.sol)                               | 178          |
| **Total**                                                              | **757**      | 

### Global state + helpers
| Contract / Method                                                       | SLOC        |
| ---------------------------------------------------------------------- | ------------ |
| [`StabilityPod/ImpliedCollateralService.sol#getCollateralizedMalt`](https://github.com/code-423n4/2023-02-malt/contracts/StabilityPod/ImpliedCollateralService.sol)  | 34           |
| [`DataFeed/MaltDataLab.sol#rewardToMaltDecimals`](https://github.com/code-423n4/2023-02-malt/contracts/DataFeed/MaltDataLab.sol)                    | 13           |
| [`DataFeed/MaltDataLab.sol#maltToRewardDecimals`](https://github.com/code-423n4/2023-02-malt/contracts/DataFeed/MaltDataLab.sol)                    | 17           |
| [`GlobalImpliedCollateralService.sol`](https://github.com/code-423n4/2023-02-malt/contracts/GlobalImpliedCollateralService.sol)                               | 189          |
| [`Repository.sol`](https://github.com/code-423n4/2023-02-malt/contracts/Repository.sol)                                                   | 196          |
| **Total**                                                              | **449**      | 

**Total sloc = 2626**

*All lines of code were counted using `cloc` tool on linux. Only lines of code are counted, not blanks / comments etc*

## Out of scope

| Contract / Directory                                 |
| ------------------------------------------------- |
| [contracts/Auction/](https://github.com/code-423n4/2023-02-malt/contracts/Auction)                |
| [contracts/DataFeed/DualMovingAverage.sol](https://github.com/code-423n4/2023-02-malt/contracts/DataFeed/DualMovingAverage.sol)                |
| [contracts/DataFeed/MovingAverage.sol](https://github.com/code-423n4/2023-02-malt/contracts/DataFeed/MovingAverage.sol)                |
| [contracts/DexHandlers/](https://github.com/code-423n4/2023-02-malt/contracts/DexHandlers)                |
| [contracts/libraries/](https://github.com/code-423n4/2023-02-malt/contracts/libraries)                |
| [contracts/ops/](https://github.com/code-423n4/2023-02-malt/contracts/ops)                |
| [contracts/RewardSystem/RewardOverflowPool.sol](https://github.com/code-423n4/2023-02-malt/contracts/RewardSystem/RewardOverflowPool.sol)                |
| [contracts/RewardSystem/VestingDistributor.sol](https://github.com/code-423n4/2023-02-malt/contracts/RewardSystem/VestingDistributor.sol)                |
| [contracts/StabilityPod/LiquidityExtension.sol](https://github.com/code-423n4/2023-02-malt/contracts/StabilityPod/LiquidityExtension.sol)                |
| [contracts/StabilityPod/ProfitDistributor.sol](https://github.com/code-423n4/2023-02-malt/contracts/StabilityPod/ProfitDistributor.sol)                |
| [contracts/StabilityPod/SwingTrader.sol](https://github.com/code-423n4/2023-02-malt/contracts/StabilityPod/SwingTrader.sol)                |
| [contracts/StabilizedPool/](https://github.com/code-423n4/2023-02-malt/contracts/StabilizedPool/)                |
| [contracts/StabilizedPoolExtensions/](https://github.com/code-423n4/2023-02-malt/contracts/StabilizedPoolExtensions/)                |
| [contracts/Staking/](https://github.com/code-423n4/2023-02-malt/contracts/Staking/)                |
| [contracts/Testnet/](https://github.com/code-423n4/2023-02-malt/contracts/Testnet/)                |
| [contracts/Token/AbstractTransferVerification.sol](https://github.com/code-423n4/2023-02-malt/contracts/Token/AbstractTransferVerification.sol)                |
| [contracts/Token/PoolTransferVerification.sol](https://github.com/code-423n4/2023-02-malt/contracts/Token/PoolTransferVerification.sol)                |
| [contracts/Permissions.sol](https://github.com/code-423n4/2023-02-malt/contracts/Permissions.sol)                |
| [contracts/Timekeeper.sol](https://github.com/code-423n4/2023-02-malt/contracts/Timekeeper.sol)                |
| [contracts/Timelock.sol](https://github.com/code-423n4/2023-02-malt/contracts/Timelock.sol)                |

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

Find the desmos graph implementing these curves (here)[https://www.desmos.com/calculator/nilxvwurmo]
The video walking through the desmos graph (here)[https://drive.google.com/file/d/1R18oZGjIcsJaWNbBVod5aNjvK_LKNJO-/view?usp=sharing]

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
