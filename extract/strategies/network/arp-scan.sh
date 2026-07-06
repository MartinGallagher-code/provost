#!/bin/bash
## Name: arp-scan
## Description: Extract discovered hosts (ip/mac/vendor) from arp-scan output
## Version: 1.0
## Priority: 20
## Sample: samples/arp-scan/basic.txt

# `arp-scan` prints a banner (Interface:/Starting ...), then one tab-separated
# row per responding host:  <ip>\t<mac>\t<vendor>, then a packet summary.

_arpscan_is_host () {
    [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[[:space:]]+([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}([[:space:]]+.*)?$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line
    while IFS= read -r line; do
        if _arpscan_is_host "$line"; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        _arpscan_is_host "$line" || continue
        read -ra _a <<< "$line"
        local ip="${_a[0]}" mac="${_a[1]}"
        local vendor=""
        local i
        for ((i=2; i<${#_a[@]}; i++)); do
            [[ -n "$vendor" ]] && vendor+=" "
            vendor+="${_a[$i]}"
        done
        entry=$((entry + 1))
        result+="entry${entry}.ip ${ip}"$'\n'
        result+="entry${entry}.mac ${mac}"$'\n'
        result+="entry${entry}.vendor ${vendor}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
