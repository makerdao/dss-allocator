#!/usr/bin/env bash

# Usage: ./run_stable_depositor.sh $CHAINID $STABLE_DEPOSITOR_ADDR $FROM_BLOCK
# Example goerli usage: ./run_stable_depositor.sh 5 0x61928e1813c8883D14a75f31F3daeE53929A45DE 9422770

set -e

CHAINID=$1
STABLE_DEPOSITOR=$2
FROM_BLOCK=${3:-"earliest"}

[[ "$ETH_RPC_URL" && "$(cast chain-id)" == "$CHAINID" ]] || { echo -e "Please set a ETH_RPC_URL pointing to chainId $CHAINID"; exit 1; }

SET_CONFIG_LOG="SetConfig(address indexed gem0, address indexed gem1, uint24 indexed fee, int24 tickLower, int24 tickUpper, int32 num, uint32 hop, uint96 amt0, uint96 amt1, uint96 req0, uint96 req1)"
DEPOSIT_SIG="deposit(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min)"
WITHDRAW_SIG="withdraw(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min)"

JSON=$(cast logs --from-block $FROM_BLOCK --to-block latest --address $STABLE_DEPOSITOR "$SET_CONFIG_LOG" --json)
echo $JSON | jq -c '.[]' | while read i; do
    gem0=$(cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[1]"))
    gem1=$(cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[2]"))
    fee=$(cast abi-decode --input "x(uint24)"  $(echo $i | jq -r ".topics[3]"))
    data=$(cast abi-decode --input "x(int24,int24)" $(echo $i | jq -r ".data"))
    tickLower=$(echo $data | cut -d" " -f1)
    tickUpper=$(echo $data | cut -d" " -f2)

    params="$gem0 $gem1 $fee $tickLower $tickUpper"
    var="handled_${params//[- ]/_}"
    if [ -z "${!var}" ]; then
        declare handled_${params//[- ]/_}=1
    else
        continue
    fi

    cfg_calldata=$(cast calldata "configs(address,address,uint24,int24,int24)" $params)
    # Note that we run `cast call` using the raw calldata to avoid issues with negative arguments
    cfg=$(cast call $STABLE_DEPOSITOR $cfg_calldata)
    decoded_cfg=$(cast abi-decode --input "x(int32,uint32,uint96,uint96,uint96,uint96,uint32)" $cfg)
    num=$(echo $decoded_cfg | cut -d" " -f1)

    if (( num > 0 )); then
        echo "Num=$num. Depositing into ($gem0, $gem1, $fee) pool..."
        sig=$DEPOSIT_SIG
    elif (( num < 0 )); then
        echo "Num=$num. Withdrawing from ($gem0, $gem1, $fee) pool..."
        sig=$WITHDRAW_SIG
    fi

    if (( num )); then
        calldata=$(cast calldata "$sig" $params 0 0)
        # Note that we run `cast estimate` and `cast send` using the raw calldata to avoid issues with negative arguments
        gas=$(cast estimate $STABLE_DEPOSITOR $calldata || true)
        [[ -z "$gas" ]] && { continue; }
        cast send --gas-limit $gas $STABLE_DEPOSITOR $calldata
    fi
done
