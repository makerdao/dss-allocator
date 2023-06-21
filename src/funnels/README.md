# Allocator funnels

## UniV3 Liquidity Deposit Funnel

TBD

## UniV3 Swapper Funnel

The `Swapper` module enables SubDAOs to perform trust-minimized NST-to-GEM or GEM-to-NST swaps that can be used in the context of a SubDAO allocation strategy. This is achieved by authorising priviledged facilitators to operate swaps within strict governance-defined bounds.

Each AllocatorBuffer has a `Swapper` contract attached to it that can be used by whitelisted facilitators to swap NST to GEM (e.g. USDC or USDT) or GEM to NST. For a NST-to-GEM swap, the NST is taken from the attached AllocatorBuffer and the GEM is sent to an `escrow` contract. For a GEM-to-NST swap, the GEM is taken from the `escrow` contract and the NST is sent to the attached AllocatorBuffer. The `Swapper` contract has a number of parameters set by MakerDAO governance:

- `escrow` [address]: The escrow contract from which the GEM to sell is pulled before a GEM-to-NST swap or to which the bought GEM is pushed after a NST-to-GEM swap (see below).
- `buffer` [address]: The allocation buffer attached to the `Swapper`
- `hop` [seconds]: Swap cooldown. A new swap can only be executed by facilitators every `hop` seconds.
- `minNstPrice` [WAD]: Relative multiplier of the reference price (equal to 1 GEM/NST) to insist on in the swap from NST to GEM. 1 WAD = 100%
- `minGemPrice` [WAD]: Relative multiplier of the reference price (equal to 1 NST/GEM) to insist on in the swap from GEM to NST. 1 WAD = 100%
- `maxNstLot` [WAD]: Max allowable `nstLot` (see below)
- `maxGemLot` [WAD]: Max allowable `gemLot` (see below)

In addition to the above parameters, Maker Governance can whitelist priviledged facilitator accounts who are tasked with interpreting the SubDAO Scope Artifacts and operate the Swapper contract accordingly. To reduce the impact of a compromised facilitator, their operation is constrained by the rate limits implied by the governance-set parameters described above. Faciliators are authorised to change the following parameters:

- `nstToGemCount` [count]: Remaining number of times that a NSG-to-GEM swap can be performed.
- `gemToNstCount` [count]: Remaining number of times that a NST-to-GEM swap can be performed.
- `nstLot` [WAD]: The amount swapped from NST to GEM every hop. Must be lower than `maxNstLot`.
- `gemLot` [WAD]: The amount swapped from GEM to NST every hop. Must be lower than `maxGemLot`.

Facilitators are also authorised to whitelist permissionned keepers to perform the actual swap calls. The only parameters that keepers need to set when calling the swap methods is the minimum amount of output tokens that must be received for the swap to succeed. To reduce the impact of compromised keepers, this minimum amount of output tokens cannot be set lower than the amount implied by the product of `{nst|gem}Lot` (set by facilitators within governance-set bounds) and `min{Nst|Gem}Price` (set by governance).

## Escrow

The escrow is the contract in which GEM (e.g. USDC or USDT) sits while not being allocated to any particular scheme. In particular, GEM is expected to sit in the `Escrow` before and after a swap. Maker governance can approve other contracts to transfer funds from the `Escrow`. The `Swapper` described above will be one such contract.
