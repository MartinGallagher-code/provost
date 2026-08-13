#!/bin/bash
## Name: proc-net-dev
## Description: Extract per-interface counters from /proc/net/dev
## Version: 1.0
## Priority: 12
## Sample: samples/proc-net-dev/basic.txt

# /proc/net/dev's two-row header defeats every generic parser:
#
#   Inter-|   Receive                             |  Transmit
#    face |bytes packets errs drop fifo frame compressed multicast|bytes ...
#      lo:       0       0    0    0    0     0          0      0        0 ...
#
# The `|` group separators and the split `Inter-`/`face` label collapse the 16
# counters into two mega-cells whose names are header words run together. The
# format itself is FIXED (kernel ABI): interface name with a colon, then 8
# receive counters and 8 transmit counters. Name them rx_*/tx_* directly.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    if [[ "$text" == *"Inter-|"*"Receive"* && "$text" == *"face |bytes"* ]]; then
        _STRATEGY_CONFIDENCE=90
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local names=(rx_bytes rx_packets rx_errs rx_drop rx_fifo rx_frame rx_compressed rx_multicast \
                 tx_bytes tx_packets tx_errs tx_drop tx_fifo tx_colls tx_carrier tx_compressed)
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Header rows carry the `|` chrome; data rows never do.
        [[ "$line" == *"|"* ]] && continue
        [[ "$line" == *:* ]] || continue
        local iface="${line%%:*}"
        iface="${iface#"${iface%%[![:space:]]*}"}"
        local rest="${line#*:}"
        local vals=()
        read -ra vals <<< "$rest"
        [[ ${#vals[@]} -ge 1 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.interface ${iface}"$'\n'
        local i
        for ((i = 0; i < ${#vals[@]} && i < ${#names[@]}; i++)); do
            result+="entry${entry}.${names[$i]} ${vals[$i]}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
