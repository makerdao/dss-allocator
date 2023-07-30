#!/usr/bin/env bash

# Usage: ./run_stable_swapper.sh $CHAINID $STABLE_SWAPPER_ADDR $CALLEE_ADDR $POOL_FEE $FROM_BLOCK
# Example goerli usage: ./run_stable_swapper.sh 5 0x4b4271cA5980a436972BEc4ad9870f773e2b3e11 0x8963f53392D35a6c9939804a924058aB981363e4 500 9416503

set -e

CHAINID=$1
STABLE_SWAPPER=$2
CALLEE=$3
POOL_FEE=$4
FROM_BLOCK=${5:-"earliest"}

[[ "$ETH_RPC_URL" && "$(cast chain-id)" == "$CHAINID" ]] || { echo -e "Please set a ETH_RPC_URL pointing to chainId $CHAINID"; exit 1; }

SET_CONFIG_LOG="SetConfig(address indexed src, address indexed dst, uint128 num, uint32 hop, uint96 lot, uint96 req)"
SWAP_SIG="swap(address src, address dst, uint256 minOut, address callee, bytes calldata data)"

declare -A config_keys

JSON=$(cast logs --from-block $FROM_BLOCK --to-block latest --address $STABLE_SWAPPER "$SET_CONFIG_LOG" --json)
echo $JSON | jq -c '.[]' | while read i; do
    src=$(cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[1]"))
    dst=$(cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[2]"))
    key="$src $dst"
    if [ -n "${config_keys[$key]}" ]; then
        continue
    else
        config_keys[$key]=1
    fi

    cfg=$(cast call $STABLE_SWAPPER "configs(address,address)(uint128 num, uint32 hop, uint96 lot, uint96)" $src $dst)
    num=$(echo $cfg | cut -d" " -f1)

    if (( num > 0 )); then
        echo "Num=$num. Swapping from $src to $dst..."
        data="$(cast concat-hex $src $(printf "%06X" $(cast to-hex $POOL_FEE)) $dst)"
        gas=$(cast estimate $STABLE_SWAPPER "$SWAP_SIG" $src $dst 0 $CALLEE $data || true)
        [[ -z "$gas" ]] && { continue; }
        cast send --gas-limit $gas $STABLE_SWAPPER "$SWAP_SIG" $src $dst 0 $CALLEE $data
    fi
done
