#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: numactl-show
## Description: Extract NUMA policy settings from `numactl --show` output
## Version: 1.0
## Priority: 9
## Sample: samples/numactl-show/basic.txt

# `numactl --show` prints one setting per line:
#   policy: default
#   preferred node: current
#   physcpubind: 0 1 2 3 4 5 6 7
#   cpubind: 0
#   nodebind: 0
#   membind: 0
# Each line is one record holding a single field: the setting name and value.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Distinctive signature: NUMA bind settings.
        [[ "$line" == "nodebind:"* || "$line" == "membind:"* ]] && return 0
    done
    return 1
}

_numa_sanitise () {
    local s="$1"
    s="${s//$'\t'/ }"
    while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *": "* ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.value $(_numa_sanitise "$line")"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
