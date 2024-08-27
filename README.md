# `dss-allocator`

Part of this code was inspired by https://github.com/makerdao/rwa-toolkit/blob/master/src/urns/RwaUrn.sol mainly authored by livnev and https://github.com/dapphub/ds-roles/blob/master/src/roles.sol authored by DappHub.
Since it should belong to the MakerDAO community the Copyright from our additions has been transferred to Dai Foundation.

## Important Update:

**The funnels in this repository and their automation contracts should now be regarded as included for illustrative purposes only. In practice, other use-case specialized funnels are expected to be built.**

**The deployment libraries, tests and the documentation below still use the specific included funnels (e.g DepositorUniV3, Swapper). Those parts should be considered as obsolete.**

## Overview
Implementation of the allocation system, based on the [technical specification forum post](https://forum.makerdao.com/t/preliminary-technical-specification-of-the-allocation-system/20921).  
The conduits are implemented separately. See for example [dss-conduits](https://github.com/makerdao/dss-conduits).

![Untitled-2023-08-07-1511](https://github.com/makerdao/dss-allocator/assets/130549691/af24bcb8-5e5a-4394-8eee-a1f7d6f44341)

## Layers
The system is comprised of several layers:

- Core Allocation System (*green above*):
    - Smart contracts that can be considered a part of the Maker Core Protocol, and are immutable and present in all Allocators.
    - Their main role is to mint USDS (New Stable Token) and hold it (possibly with other tokens) in the `AllocatorBuffer`.
- Deployment Funnels (*blue above*):
    - Contracts that pull funds from the `AllocatorBuffer`.
    - The funds can be swapped and/or deployed into AMM pools or specific conduits.
    - A typical setting for a funnel includes a base rate-limited contract (such as Swapper) and an automation contract on top of it (such as StableSwapper).
- Conduits (*orange above*):
    - Yield investment singletons that support deposits and withdrawals.

## Actors
The allocation system includes several actor types:

- Pause Proxy:
    - Performs actions through spells with governance delay.
    - In charge of setting up the core components and the USDS minting instant access modules (DC-IAMs).
    - Ward of the singleton contracts (e.g RWA conduits, Coinbase Custody, `AllocatorRoles`).
- AllocatorDAO Proxy:
    - Performs actions through a sub-spell with governance delay.
    - Ward of its `AllocatorVault`, `AllocatorBuffer` and funnel contracts.
    - In charge of adding new contracts to the funnel network (e.g Swapper, DepositorUniV3).
    - Can add operators to its funnel network through the `AllocatorRoles` contract.
    - In charge of setting rate-limiting safety parameters for operators.
- Operator:
    - Performs actions without a spell and without governance delay.
    - An optional actor which is whitelisted through the `AllocatorRoles` contract to perform specified actions on the `AllocatorVault`, funnels and conduits.
    - Will typically be a facilitator multisig or an automation contract controlled by one (e.g `StableSwapper`, `StableDepositorUniV3`).
- Keeper:
    - An optional actor which can be set up to trigger the automation contracts in case repetitive actions are needed (such as swapping USDS to USDC every time interval).

![Untitled (1)](https://github.com/makerdao/dss-allocator/assets/130549691/c677928b-32f4-4000-b6ed-e3798caa9c5c)

## Contracts and Configuration
### VAT Configuration

Each AllocatorDAO has a unique `ilk` (collateral type) with one VAT vault set up for it.

- All the `ilk`s have a shared simple [oracle](https://github.com/makerdao/dss-allocator/blob/dev/src/AllocatorOracle.sol) that just returns a fixed price of 1:1 (which multiplied by a huge amount of collateral makes sure the max debt ceiling can indeed be reached). In case it is necessary a governance spell could also increase it further.

### AllocatorVault

Single contract per `ilk`, which operators can use to:

- Mint (`draw`) USDS from the vault to the AllocatorBuffer.
- Repay (`wipe`) USDS from the AllocatorBuffer.

### AllocatorBuffer

A simple contract for the AllocatorDAO to hold funds in.

- Supports approving contracts to `transferFrom` it.
- Note that although the `AllocatorVault` pushes and pulls USDS to/from the `AllocatorBuffer`, it can manage other tokens as well.

### AllocatorRoles

A global permissions registry, inspired by [ds-roles](https://github.com/dapphub/ds-roles).

- Allows AllocatorDAOs to list operators to manage `AllocatorVault`s, funnels and conduits in a per-action resolution.
- Warded by the Pause Proxy, which needs to add a new AllocatorDAO once one is onboarded.

### AllocatorRegistry

A registry where each AllocatorDAO’s `AllocatorBuffer` address is listed.

### Swapper

A module that pulls tokens from the `AllocatorBuffer` and sends them to be swapped at a callee contract. The resulting funds are sent back to the `AllocatorBuffer`.

It enforces that:

- The swap rate is not faster than a pre-configured rate.
- The amount to swap each time is not larger than a pre-configured amount.
- The received funds are not less than a minimal amount specified on the swap call.

### Swapper Callees

Contracts that perform the actual swap and send the resulting funds to the Swapper (to be forwarded to the AllocatorBuffer).

- They can be implemented on top of any DEX / swap vehicle.
- An example is `SwapperCalleeUniV3`, where swaps in Uniswap V3 can be triggered.

### DepositorUniV3

A primitive for depositing liquidity to Uniswap V3 in a fixed range. 

As the Swapper, it includes rate limit protection and is designed so facilitators and automation contracts can use it.

### VaultMinter

An automation contract sample, which can be used by the AllocatorDAOs to `draw` or `wipe` from/to the `AllocatorVault`.
- It can be useful for automating generation of funds from the vault to the buffer or repayment from the buffer to the vault.

### StableSwapper

An automation contract, which can be used by the AllocatorDAOs to set up recurring swaps of stable tokens (e.g USDS to USDC).

- In order to use it, the AllocatorDAO should list it as an operator of its `Swapper` primitive in the `AllocatorRoles` contract.
- The `Swapper` primitive will rate-limit the automation contract.

### StableDepositorUniV3

An automation contract sample, which can be used by the AllocatorDAOs to set up recurring deposits or withdraws. 

- In order to use it, the AllocatorDAO should list it as an operator of its `DepositorUniV3` primitive in the `AllocatorRoles` contract.
- The `Depositor` primitive will rate-limit the automation contract.

### ConduitMover

An automation contract sample, which can be used by the AllocatorDAOs to move funds between their `AllocatorBuffer` and the conduits in an automated manner.
- Although there is no built-in rate limit in the transfer of funds from/to the `AllocatorBuffer` to/form the conduits,
this can be useful for optimizing yield by moving funds to the destination conduit just in time for them to get processed
(in case the destination conduit has an agreed upon rate limiting).
- It can also be useful for automating movement of funds from the buffer in the same rate as they are swapped or withdrawn into it.

### IAllocatorConduit

An interface which each Conduit should implement.

## Security Model:
- AllocatorDAOs can not incur a loss of more than the debt ceiling (`line`) of their respective `ilk`.
- A funnel operator (whether a facilitator or an automated contract) can not incur a loss of more than `cap` amount of funds per `era` interval for a specific configuration. This includes not being able to move funds directly to any unknown address that the AllocatorDAO Proxy did not approve.
- A keeper's maximum loss must be bounded by `cap` amount of funds per `era` (as for a funnel operator) but is additionally constrainted by `lot` (or `amt0` and `amt1`) amount of funds per `hop` for a specific configuration. Moreover, a keeper's execution must guarantee a minimum amount of output tokens, defined by `req` (or `req0` and `req1`) for a specific configuration.
- If a rate limit is needed for depositing or withdrawing in a specific Conduit (in order to limit the harm a rogue facilitator can cause), it is the responsibility of the Conduit itself to implement it.

## Technical Assumptions:
- A `uint32` is suitable for storing timestamps or time intervals in the funnels, as the current version of the Allocation System is expected to be deprecated long before 2106.
- A `uint96` is suitable for storing token amounts in the funnels, as amounts in the scale of 70B are not expected to be used. This implies that the Allocation System does not support tokens with extremely low prices.
- As with most MakerDAO contracts, non standard token implementations are assumed to not be supported. As examples, this includes tokens that:
  * Do not have a decimals field or have more than 18 decimals.
  * Do not revert and instead rely on a return value.
  * Implement fee on transfer.
  * Include rebasing logic.
  * Implement callbacks/hooks.
- In the Swapper, in case `limit.era` is zero the full cap amount can be swapped for multiple times in the same transaction because `limit.due` will be reset upon re-entry. However, this is consistent with the intended behavior, as in that case zero cooldown is explicitly defined.
- In StableSwapper the keeper's minimal out value is assumed to be updated whenever `configs[src][dst]` is changed. Failing to do so may result in the swap call reverting or in taking on more slippage than intended (up to a limit controlled by `configs[src][dst].min`).
- In StableDepositorUniV3 the keeper's minimal amt values are assumed to be updated whenever `configs[gem0][gem1][fee][tickLower][tickUpper]` is changed. Failing to do so may result in the deposit/withdraw call reverting or in taking on more slippage than intended (up to a limit controlled by `configs[gem0][gem1][fee][tickLower][tickUpper].req0/1`).
- Deployment sanity checks are done as part of the init functions (see the `deploy` directory).
- DepositorUniV3 has limits for the maximum amount of a pair of tokens that can be added or removed from the pool per era. The rate is purposefully shared between the deposit and withdraw operations (so both actions share the same capacity).
- The AllocatorDAO Proxy configuring the different rate limits is assumed to know what it is doing and is allowed to set any configuration, even if one configuration collides or duplicates others.
- The Allocation System assumes that the ESM threshold is set large enough prior to its deployment, so Emergency Shutdown can never be called.
