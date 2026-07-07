#!/bin/bash
## Name: ifstat
## Description: Extract per-interface throughput samples from `ifstat` output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/ifstat/basic.txt

# `ifstat` prints a two-line header: interface names on the first line, then a
# `KB/s in  KB/s out` sub-header (two columns per interface), then one sample
# row per interval:
#     eth0                wlan0
#  KB/s in  KB/s out   KB/s in  KB/s out
#    12.45     3.21       0.98      0.12
# We emit one record per sample, with <iface>_in / <iface>_out columns.

# Safe field-name fragment (word chars only).
_ifstat_name () { printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_' | sed 's/_\{1,\}/_/g; s/^_//; s/_$//'; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *"KB/s in"* && "$text" == *"KB/s out"* ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0 idx=0
    local -a ifaces=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        idx=$((idx + 1))

        if [[ $idx -eq 1 ]]; then
            read -ra ifaces <<< "$line"
            continue
        fi
        [[ $idx -eq 2 ]] && continue   # KB/s in / KB/s out sub-header

        local -a vals=()
        read -ra vals <<< "$line"
        local ni=${#ifaces[@]}
        [[ $ni -eq 0 ]] && continue
        [[ ${#vals[@]} -lt $((2 * ni)) ]] && continue

        n=$((n + 1))
        local k
        for ((k=0; k<ni; k++)); do
            local nm; nm=$(_ifstat_name "${ifaces[$k]}")
            result+="entry${n}.${nm}_in ${vals[$((2*k))]}"$'\n'
            result+="entry${n}.${nm}_out ${vals[$((2*k+1))]}"$'\n'
        done
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
