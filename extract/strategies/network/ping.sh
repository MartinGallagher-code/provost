#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: ping
## Description: Extract per-reply records from ping output (seq, ttl, time, from)
## Version: 1.0
## Priority: 14
## Sample: samples/ping-reply/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # Distinctive signature: an ICMP reply line carries BOTH "bytes from" and
    # "icmp_seq=" on the same line.
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" == *"bytes from "* && "$line" == *"icmp_seq="* ]]; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # One record per reply line (skip header / stats / summary lines).
        [[ "$line" == *"bytes from "* && "$line" == *"icmp_seq="* ]] || continue

        local from="" seq="" ttl="" time=""

        # from: token after "from ", trailing ':' stripped
        local after="${line#*bytes from }"
        from="${after%%:*}"
        # trim surrounding whitespace
        from="${from#"${from%%[![:space:]]*}"}"
        from="${from%"${from##*[![:space:]]}"}"

        [[ "$line" =~ icmp_seq=([0-9]+) ]] && seq="${BASH_REMATCH[1]}"
        [[ "$line" =~ ttl=([0-9]+) ]] && ttl="${BASH_REMATCH[1]}"
        [[ "$line" =~ time=([0-9.]+) ]] && time="${BASH_REMATCH[1]}"

        entry=$((entry + 1))
        [[ -n "$seq" ]]  && result+="entry${entry}.seq ${seq}"$'\n'
        [[ -n "$ttl" ]]  && result+="entry${entry}.ttl ${ttl}"$'\n'
        [[ -n "$time" ]] && result+="entry${entry}.time ${time}"$'\n'
        [[ -n "$from" ]] && result+="entry${entry}.from ${from}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
