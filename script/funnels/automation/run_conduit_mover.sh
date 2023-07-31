#!/usr/bin/env bash

# Usage: ./run_conduit_mover.sh $CHAINID $CONDUIT_MOVER_ADDR $FROM_BLOCK
# Example goerli usage: ./run_conduit_mover.sh 5 0x04e02dEa98410758e52cd0c47F07d9cc0fb15566 9440653

set -e

CHAINID=$1
CONDUIT_MOVER=$2
FROM_BLOCK=${3:-"earliest"}

[[ "$ETH_RPC_URL" && "$(cast chain-id)" == "$CHAINID" ]] || { echo -e "Please set a ETH_RPC_URL pointing to chainId $CHAINID"; exit 1; }

SET_CONFIG_LOG="SetConfig(address indexed from, address indexed to, address indexed gem, uint64 num, uint32 hop, uint128 lot)"
MOVE_SIG="move(address from, address to, address gem)"

JSON=$(cast logs --from-block $FROM_BLOCK --to-block latest --address $CONDUIT_MOVER "$SET_CONFIG_LOG" --json)
echo $JSON | jq -c '.[]' | while read i; do
    from=$(cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[1]"))
    to=$(  cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[2]"))
    gem=$( cast abi-decode --input "x(address)" $(echo $i | jq -r ".topics[3]"))

    params="$from $to $gem"
    var="handled_${params// /_}"
    if [ -z "${!var}" ]; then
        declare handled_${params// /_}=1
    else
        continue
    fi

    cfg=$(cast call $CONDUIT_MOVER "configs(address,address,address)(uint64,uint32,uint32,uint128)" $params)
    num=$(echo $cfg | cut -d" " -f1)

    if (( num > 0 )); then
        echo "Num=$num. Moving $gem from conduit $from to conduit $to..."
        gas=$(cast estimate $CONDUIT_MOVER "$MOVE_SIG" $params || true)
        [[ -z "$gas" ]] && { continue; }
        cast send --gas-limit $gas $CONDUIT_MOVER "$MOVE_SIG" $params
    fi
done
