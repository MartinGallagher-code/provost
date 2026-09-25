#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: mtr-report
## Description: Extract per-hop path statistics from an mtr report
## Version: 1.0
## Priority: 17
## Sample: samples/mtr-report/basic.txt

# `mtr --report` prints a "HOST:" header followed by one row per hop:
#   1.|-- gateway   0.0%   10   1.2  1.4  1.1  2.3  0.4
# Columns after the host are: Loss% Snt Last Avg Best Wrst StDev.
# Priority 17 so it beats the generic tree-view (p50) on the "N.|--" marker.

_mtr_is_hop () {
    [[ "$1" =~ ^[[:space:]]*[0-9]+\.\|--[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local has_header=0 has_hop=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == HOST:* || "$line" == *"HOST:"*"Loss%"* ]] && has_header=1
        _mtr_is_hop "$line" && has_hop=1
    done
    if [[ $has_header -eq 1 && $has_hop -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _mtr_is_hop "$line" || continue
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        local hop="${trimmed%%.*}"
        local after="${trimmed#*|-- }"
        { _fr_tok "$after"; _a=("${_FR_TOK[@]}"); }
        # _a: host loss snt last avg best wrst stdev
        local host="${_a[0]}" loss="${_a[1]}" snt="${_a[2]}"
        local last="${_a[3]}" avg="${_a[4]}"
        entry=$((entry + 1))
        result+="entry${entry}.hop ${hop}"$'\n'
        result+="entry${entry}.host ${host}"$'\n'
        result+="entry${entry}.loss ${loss}"$'\n'
        result+="entry${entry}.snt ${snt}"$'\n'
        result+="entry${entry}.last ${last}"$'\n'
        result+="entry${entry}.avg ${avg}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
