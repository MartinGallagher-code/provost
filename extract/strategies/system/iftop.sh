#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: iftop
## Description: Extract per-direction connection records from iftop output (host, peer, rates)
## Version: 1.0
## Priority: 20
## Sample: samples/iftop/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: iftop's cumulative-rate table and totals.
    if [[ "$text" == *"Total send and receive rate"* ]] \
       || { [[ "$text" == *"cumulative"* ]] && [[ "$text" == *"=>"* ]] && [[ "$text" == *"<="* ]]; }; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local last_host="" last_peer=""
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Skip separator rules and the Total summary lines.
        [[ "$line" == *"Total"* ]] && continue

        local v
        read -ra v <<< "$line"

        local direction="" host="" peer="" r2="" r10="" r40="" cum=""
        if [[ "${v[1]:-}" == "=>" ]]; then
            # "<host> => <peer>  <2s> <10s> <40s> <cumulative>"
            [[ ${#v[@]} -lt 7 ]] && continue
            direction="send"
            host="${v[0]}"; peer="${v[2]}"
            r2="${v[3]}"; r10="${v[4]}"; r40="${v[5]}"; cum="${v[6]}"
            last_host="$host"; last_peer="$peer"
        elif [[ "${v[0]:-}" == "<=" ]]; then
            # "<= <2s> <10s> <40s> <cumulative>" (host/peer from prior => row)
            [[ ${#v[@]} -lt 5 ]] && continue
            direction="recv"
            host="$last_host"; peer="$last_peer"
            r2="${v[1]}"; r10="${v[2]}"; r40="${v[3]}"; cum="${v[4]}"
        else
            continue
        fi

        entry=$((entry + 1))
        result+="entry${entry}.host ${host}"$'\n'
        result+="entry${entry}.direction ${direction}"$'\n'
        result+="entry${entry}.peer ${peer}"$'\n'
        result+="entry${entry}.last_2s ${r2}"$'\n'
        result+="entry${entry}.last_10s ${r10}"$'\n'
        result+="entry${entry}.last_40s ${r40}"$'\n'
        result+="entry${entry}.cumulative ${cum}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
