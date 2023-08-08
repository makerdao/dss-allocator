# `dss-conduits`

Part of this code was inspired by https://github.com/makerdao/rwa-toolkit/blob/master/src/urns/RwaUrn.sol mainly authored by livnev and https://github.com/dapphub/ds-roles/blob/master/src/roles.sol authored by DappHub.
Since it should belong to the MakerDAO community the Copyright from our additions has been transferred to Dai Foundation.

## Overview
Implementation of the allocation system, based on the [technical specification forum post](https://forum.makerdao.com/t/preliminary-technical-specification-of-the-allocation-system/20921
).

![Untitled](https://github.com/makerdao/dss-allocator/assets/130549691/388f20fa-2d0c-484b-b716-fe4fa742115b)


## Layers
The system is comprised of several layers:

- Core Allocation System (*green above*):
    - Smart contracts that can be considered a part of the Maker Core Protocol, and are immutable and present in all Allocators.
    - Their main role is to mint NST (New Stable Token) and hold it (possibly with other tokens) in the AllocationBuffer.
- Deployment Funnels (*blue above*):
    - Contracts that pull funds from the AllocatorBuffer.
    - The funds can either be swapped or deployed into AMM pools or specific conduits.
    - A typical setting for a funnel includes a base rate limited contract (such as Swapper) and an automation contract on top of it (such as StableSwapper).
- Conduits (*orange above*):
    - Yield investment singletons that support deposits and withdrawals.

## Actors
The allocation system includes several actor types:

- Pause Proxy:
    - Performs actions through spells with governance delay.
    - In charge of setting up the core components and the NST minting instant access modules (DC-IAMs).
    - Ward of the singleton contracts (e.g RWA conduits, Coinbase Custody, AllocatorRoles).
- AllocatorDao Proxy:
    - Performs actions through a sub-spell with governance delay.
    - Ward of its AllocatorVault and its funnel contracts.
    - In charge of adding new contracts to the funnel network (e.g Swapper, DepositorUniv3).
    - Can add operators to its funnel network through the AllocatorRoles contract.
    - In charge of setting rate-limiting safety parameters for operators.
- Operator:
    - Performs actions without a spell and without governance delay.
    - An optional actor which is whitelisted through the AllocatorRoles contract to perform specified actions on the AllocatorVault, funnels and conduits.
    - Will typically be a facilitator multisig or an automation contract controlled by one (e.g StableSwapper, StableDepositorUniv3).
- Keeper:
    - An optional actor which can be set up to trigger the automation contracts in case repetitive actions are needed (such as swapping NST to USDC every time interval).

![Untitled (1)](https://github.com/makerdao/dss-allocator/assets/130549691/c677928b-32f4-4000-b6ed-e3798caa9c5c)

## Contracts and Configuration
### VAT Configuration

Each AllocatorDAO has a unique Ilk (collateral type) with one VAT vault set up for it.

- Each ilk supports a 1 trillion NST debt ceiling.
- Each Ilk has a special collateral token that is minted and locked in the system.
- The collateral amount of each vault is 1 million NST.
- All the Ilks have a shared simple [oracle](https://github.com/makerdao/dss-allocator/blob/dev/src/AllocatorOracle.sol) that just returns a fixed price of 1 Million (which multiplied by the collateral amount makes sure the debt ceiling can indeed be reached).

### AllocatorVault

Single contract per Ilk, which operators can use to:

- Mint (`draw` ) NST from the vault to the AllocatorBuffer.
- Repay (`wipe`) NST from the AllocatorBuffer.

### AllocatorBuffer

A simple contract for the AllocatorDAO to hold funds in.

- Supports approving contracts to `transferFrom` it.
- Note that although the AllocatorVault pushes and pulls NST to/from the AllocationBuffer, it can manage other tokens as well.

### AllocatorRoles

A global permissions registry, inspired by [ds-roles](https://github.com/dapphub/ds-roles).

- Allows AllocatorDaos to list operators to manage AllocatorVaults, funnels and conduits in a per-action resolution.
- Warded by the Pause Proxy, which needs to add a new AllocatorDao once one is onboarded.

### AllocatorRegistry

A registry where each AllocatorDao’s AllocatorBuffer address is listed.

### Swapper

A module that pulls tokens from the AllocationBuffer and sends them to be swapped at a callee contract. The resulting funds are sent back to the AllocationBuffer.

It enforces that:

- The swap rate is not faster than a pre-configured rate.
- The amount to swap each time is not larger than a pre-configured amount.
- The received funds are not less than a minimal amount specified on the swap call.

### Swapper Callees

Contracts that perform the actual swap and send the resulting funds to the Allocation Buffer.

- They can be implemented on top of any DEX / swap vehicle.
- An example is SwapperCalleeUniV3, where swaps in Uniswap V3 can be triggered.

### DepositorUniV3

A primitive for depositing liquidity to Uniswap V3 in a fixed range. 

As the Swapper, it includes rate limit protection and is designed so facilitators and automation contracts can use it.

### StableSwapper

An automation contract, which can be used by the AllocatorDaos to set up recurring swaps of stable tokens (e.g NST to USDC).

- In order to use it the AllocatorDao should list it as an operator of its Swapper primitive in the AllocatorRoles contract.
- The Swapper primitive will rate-limit the automation contract.

### StableDepositorUniV3

An automation contract sample, which can be used by the AllocatorDaos to set up recurring deposits or withdraws. 

- In order to use it the AllocatorDao should list it as an operator of its DepositorUniv3 primitive in the AllocatorRoles contract.
- The Depositor primitive will rate-limit the automation contract.

### ConduitMover

An automation contract sample, which can be used by the AllocatorDaos to move funds between their AllocatorBuffer and the conduits in an automated manner.

### IAllocatorConduit

An interface which each Conduit should implement.
