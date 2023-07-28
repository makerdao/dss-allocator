#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(cast chain)" == "goerli" && "$(cast chain-id)" == "5" ]] || { echo -e "Please set a Goerli ETH_RPC_URL"; exit 1; }

STABLE_DEPOSITOR="0x61928e1813c8883D14a75f31F3daeE53929A45DE"
FROM_BLOCK=9422770
SET_CONFIG_LOG="SetConfig(address indexed gem0, address indexed gem1, uint24 indexed fee, int24 tickLower, int24 tickUpper, int32 num, uint32 hop, uint96 amt0, uint96 amt1, uint96 req0, uint96 req1)"
DEPOSIT_SIG="deposit(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min)"
WITHDRAW_SIG="withdraw(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min)"

declare -A config_keys

JSON=$(cast logs --from-block $FROM_BLOCK --to-block latest --address $STABLE_DEPOSITOR "$SET_CONFIG_LOG" --json)
echo $JSON | jq -c '.[]' | while read i; do
    gem0=$(cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[1]"))
    gem1=$(cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[2]"))
    fee=$(cast abi-decode --input "x(uint24)"  $(echo $i | jq -r ".topics[3]"))
    data=$(cast abi-decode --input "x(int24,int24)" $(echo $i | jq -r ".data"))
    tickLower=$(echo $data | cut -d" " -f1)
    tickUpper=$(echo $data | cut -d" " -f2)
    key="$gem0 $gem1 $fee $tickLower $tickUpper"
    if [ -n "${config_keys[$key]}" ]; then
        continue
    else
        config_keys[$key]=1
    fi

    cfg_calldata=$(cast calldata "configs(address,address,uint24,int24,int24)" $key)
    # Note that we run `cast call` using the raw calldata to avoid issues with negative arguments
    cfg=$(cast call $STABLE_DEPOSITOR $cfg_calldata)
    decoded_cfg=$(cast abi-decode "configs(address,address,uint24,int24,int24)(int32,uint32,uint96,uint96,uint96,uint96,uint32)" $cfg)
    num=$(echo $decoded_cfg | cut -d" " -f1)

    if (( num > 0 )); then
        echo "Num=$num. Depositing into ($gem0, $gem1, $fee) pool..."
        calldata=$(cast calldata "$DEPOSIT_SIG" $key 0 0)
        # Note that we run `cast send` using the raw calldata to avoid issues with negative arguments
        cast send $STABLE_DEPOSITOR $calldata || true
    elif (( num < 0 )); then
        echo "Num=$num. Withdrawing from ($gem0, $gem1, $fee) pool..."
        calldata=$(cast calldata "$WITHDRAW_SIG" $key 0 0)
        # Note that we run `cast send` using the raw calldata to avoid issues with negative arguments
        cast send $STABLE_DEPOSITOR $calldata || true
    fi
done
