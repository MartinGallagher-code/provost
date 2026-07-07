#!/bin/bash
## Name: proc-buddyinfo
## Description: Extract per-zone free-page order counts from /proc/buddyinfo
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/proc-buddyinfo/basic.txt

# /proc/buddyinfo has one row per (node, zone):
#   Node 0, zone   Normal  18234  12043  8123  ...  203
# The columns after the zone name are the free-block counts for orders 0..10.
# We emit one record per line: node, zone, order0..order10 (11 orders).
# Distinct from /proc/pagetypeinfo (which adds a ", type <migratetype>" column).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == Node* ]] || return 1
    [[ "$text" == *", zone"* ]] || return 1
    [[ "$text" == *", type"* ]] && return 1         # that is pagetypeinfo
    [[ "$text" == *"Free pages count"* ]] && return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == Node*", zone"* ]] || continue

        local -a f=()
        read -ra f <<< "$line"
        # f: Node <node>, zone <zonename> <order0> ... <order10>
        [[ ${#f[@]} -lt 15 ]] && continue

        local node="${f[1]%,}" zone="${f[3]}"
        n=$((n + 1))
        result+="entry${n}.node ${node}"$'\n'
        result+="entry${n}.zone ${zone}"$'\n'
        local i
        for ((i = 0; i <= 10; i++)); do
            result+="entry${n}.order${i} ${f[$((4 + i))]}"$'\n'
        done
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
