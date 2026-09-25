#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: arping
## Description: Extract ARP reply records from `arping` output (skips banner + stats footer)
## Version: 1.0
## Priority: 26
## Sample: samples/arping/basic.txt

# arping prints a banner ("ARPING <ip>"), one line per reply
# ("<N> bytes from <mac> (<ip>): index=<seq> time=<t> msec"), then a stats
# footer ("--- <ip> statistics ---", "<n> packets transmitted…", "rtt …").
# Only the reply lines are data; the banner and footer are skipped. Each reply
# becomes a record with seq / from_ip / mac / time_msec (plus bytes).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local replies=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ ^[0-9]+\ bytes\ from\ [0-9A-Fa-f:]+\ \([0-9.]+\):\ index=[0-9]+\ time=[0-9.]+\ msec$ ]]; then
            replies=$((replies + 1))
        fi
    done
    if [[ $replies -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        [[ "$line" =~ ^[0-9]+\ bytes\ from\ [0-9A-Fa-f:]+\ \([0-9.]+\):\ index=[0-9]+\ time=[0-9.]+\ msec$ ]] || continue
        local bytes="${line%% bytes*}"
        local rest="${line#* bytes from }"
        local mac="${rest%% *}"
        local ip="${rest#*\(}"; ip="${ip%%\)*}"
        local seq="${line##*index=}"; seq="${seq%% *}"
        local t="${line##*time=}"; t="${t%% *}"
        entry=$((entry + 1))
        result+="entry${entry}.seq ${seq}"$'\n'
        result+="entry${entry}.from_ip ${ip}"$'\n'
        result+="entry${entry}.mac ${mac}"$'\n'
        result+="entry${entry}.time_msec ${t}"$'\n'
        result+="entry${entry}.bytes ${bytes}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
