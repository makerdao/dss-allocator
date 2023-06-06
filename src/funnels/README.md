# Allocator funnels

## UniV3 Liquidity Deposit Funnel

TBD

## UniV3 Swap Funnel

### Swapper

The Swapper module enables SubDAOs to perform trust-minimized NST-to-GEM or GEM-to-NST swaps that can be used in the context of a SubDAO allocation strategy.

Each AllocatorBuffer has a Swapper contract attached to it that can be used by whitelisted facilitators to swap NST to GEM (e.g. USDC or USDT) or GEM to NST. For a NST-to-GEM swap, the NST is taken from the attached AllocatorBuffer and the GEM is sent to a `dst` contract. For a GEM-to-NST swap, the GEM is taken from a `src` contract and the NST is sent to the attached AllocatorBuffer. The Swapper contract has a number of parameters set by MakerDAO governance:

- `whitelist` [address]: The contract controlling the list of authorised conduits (boxes) and routers that can be used as `src` or `dst` for this Swapper (see below).
- `buffer` [address]: The allocation buffer attached to the Swapper
- `hop` [seconds]: Swap cooldown. A new swap can only be executed by facilitators every `hop` seconds.
- `minNstPrice` [WAD]: Relative multiplier of the reference price (equal to 1 GEM/NST) to insist on in the swap from NST to GEM. 1 WAD = 100%
- `minGemPrice` [WAD]: Relative multiplier of the reference price (equal to 1 NST/GEM) to insist on in the swap from GEM to NST. 1 WAD = 100%
- `maxNstLot` [WAD]: Max allowable `nstLot` (see below)
- `maxGemLot` [WAD]: Max allowable `gemLot` (see below)

In addition to the above parameters, Maker Governance can whitelist priviledged facilitator accounts who are tasked with interpreting the SubDAO Scope Artifacts and operate the Swapper contract accordingly. To reduce the impact of a compromised facilitator, their operation is constrained by the rate limits implied by the governance-set parameters described above. Faciliators are authorised to change the following parameters:

- `src` [address]: The contract from which the GEM to sell is pulled before a GEM-to-NST swap. This can be a GEM conduit (aka "box") or alternatively a router contract responsible for collecting the GEM from multiple conduits/boxes. The `src` contract must be present in the `whitelist` contract.
- `dst` [address]: The contract to which the bought GEM is pushed after a NST-to-GEM swap. This can be an GEM conduit (aka "box") or alternatively a router contract responsible for dispatching the GEM to multiple conduits/boxes. The `dst` contract must be present in the `whitelist` contract.
- `nstToGemCount` [count]: Remaining number of times that a NSG-to-GEM swap can be performed.
- `gemToNstCount` [count]: Remaining number of times that a NST-to-GEM swap can be performed.
- `nstLot` [WAD]: The amount swapped from NST to GEM every hop. Must be lower than `maxNstLot`.
- `gemLot` [WAD]: The amount swapped from GEM to NST every hop. Must be lower than `maxGemLot`.

Facilitators are also authorised to whitelist permissionned keepers to perform the actual swap calls. The only parameters that keepers need to set when calling the swap methods is the minimum amount of output tokens that must be received for the swap to succeed. To reduce the impact of compromised keepers, this minimum amount of output tokens cannot be set lower than the amount implied by the product of `{nst|gem}Lot` (set by facilitators within governance-set bounds) and `min{Nst|Gem}Price` (set by governance).

### Router

As an alternative to setting the `src` and/or `dst` accounts of the Swapper to GEM conduits/boxes, these accounts can instead be set to `Router` contracts. `Router` contracts are used to collect GEM from (or dispatch GEM to) multiple authorised conduits/boxes. Maker governance can control `Router` contracts via the following parameters:

- `whitelist` [address]: The contract controlling the list of authorised conduits (boxes) for this Router. This is normally the same contract as the `whitelist` contract of the Swapper.

In order to be able to quickly change the mix of boxes into which GEM is pushed (or from which GEM is pulled), Maker governance can whitelist priviledged facilitator accounts who are tasked with interpreting the SubDAO Scope Artifact and are authorised to change the following parameters:

- `weights` [array of (box: address, percentage: WAD) tuples]: The allocation weights controlling in what proportion GEM should be pushed to (or pulled from) a mix of authorised boxes (e.g. 20% to Box A, 80% to Box B). The box addresses in this array must be present in the `whitelist` contract.

### Whitelist

Maker governance controls which conduits/boxes or routers can be used as `dst` or `src` in the Swapper, or which conduits/boxes can be used in the `Router` via this contract. Maker governance can update the following mapping:

- `buds` [address set]: The whitelisted GEM conduits/boxes that can be used as destinations (or sources) of the GEM pushed to (or pulled from) a `Router` that uses this `Whitelist` contract, as well as the GEM conduit/boxes or routers that can be used as `dst` or `src` address in the `Swapper` contract that uses this `Whitelist` contract.
