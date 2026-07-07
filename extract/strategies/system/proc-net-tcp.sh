#!/bin/bash
## Name: proc-net-tcp
## Description: Extract TCP socket table rows from /proc/net/tcp
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/proc-net-tcp/basic.txt

# /proc/net/tcp has a fixed header:
#   sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode
# then one hex-encoded record per socket. We keep the named leading columns and
# preserve the remaining trailing fields as col13.. so nothing is dropped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *"local_address"* ]] || return 1
    [[ "$text" == *"rem_address"* ]] || return 1
    [[ "$text" == *"tx_queue"* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0
    local names="sl local_address rem_address st tx_queue rx_queue tr tm_when retrnsmt uid timeout inode"
    local -a hn=()
    read -ra hn <<< "$names"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *"local_address"* ]] && continue   # header

        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -lt 12 ]] && continue
        [[ "${f[0]}" == *: ]] || continue                # data rows are "N:"

        n=$((n + 1))
        result+="entry${n}.sl ${f[0]%:}"$'\n'
        local i
        for ((i = 1; i < ${#f[@]}; i++)); do
            local col="${hn[$i]:-col$i}"
            result+="entry${n}.${col} ${f[$i]}"$'\n'
        done
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
