#!/bin/bash
## Name: mii-tool
## Description: Extract per-interface link status from `mii-tool -v` output
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/mii-tool/basic.txt

# `mii-tool -v` prints one line per network interface:
#   eth0: negotiated 1000baseT-FD flow-control, link ok
#   eth1: negotiated 100baseTx-FD, link ok
#   eth2: no link
#   wlan0: negotiated 100baseTx-HD, link ok
# Each line is "<iface>: <status>". We emit one record per interface holding the
# interface name and its status text.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line
    while IFS= read -r line; do
        # Distinctive: an "<iface>: ..." line mentioning link/negotiation state.
        if [[ "$line" == *": "* && ( "$line" == *"link ok"* || "$line" == *"negotiated"* ) ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

_mii_sanitise () {
    local s="$1"
    s="${s//$'\t'/ }"
    while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "${s// /_}"
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ "$line" == *": "* ]] || continue
        local iface="${line%%: *}"
        local status="${line#*: }"
        # Only treat plausible interface lines (single-token name, no spaces).
        [[ "$iface" == *" "* ]] && continue
        [[ -z "$iface" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.iface $(_mii_sanitise "$iface")"$'\n'
        result+="entry${entry}.status $(_mii_sanitise "$status")"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
