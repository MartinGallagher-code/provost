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
# Columns after the host are named by the header (Loss% Snt Last Avg Best
# Wrst StDev, or whatever subset/extension -o chose). `mtr -z` (--aslookup)
# adds an AS column before the host, and some builds drop the `|--` marker:
#   1. AS???    10.0.0.1     0.0%   10   0.4  0.5  0.3  1.1  0.2
# Priority 17 so it beats the generic tree-view (p50) on the "N.|--" marker.

# A hop row: `N.|-- host …`, or `N. host …` (no marker). The detector needs
# the HOST:/Loss% header as well, so a bare numbered list never qualifies.
_mtr_is_hop () {
    [[ "$1" =~ ^[[:space:]]*[0-9]+\.(\|--)?[[:space:]]+[^[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *HOST:* ]] || return 1
    local has_header=0 has_hop=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == HOST:* || "$line" == *"HOST:"*"Loss%"* ]] && has_header=1
        _mtr_is_hop "$line" && has_hop=1
    done
    if [[ $has_header -eq 1 && $has_hop -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=92
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line names=() _n
    _fr_lines "$text"
    # Value column names from the header: the tokens after `HOST: <name>`,
    # lowercased, `%` dropped (Loss% -> loss). Default: the --report set.
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *"HOST:"* ]] || continue
        _fr_tok "${line#*HOST:}"
        local _t=("${_FR_TOK[@]}") _i
        for ((_i = 1; _i < ${#_t[@]}; _i++)); do
            _n="${_t[$_i]//%/}"; _n="$(printf '%s' "$_n" | tr 'A-Z' 'a-z')"
            [[ -n "$_n" ]] && names+=("$_n")
        done
        break
    done
    [[ ${#names[@]} -eq 0 ]] && names=(loss snt last avg best wrst stdev)
    for line in "${_FR_LINES[@]}"; do
        _mtr_is_hop "$line" || continue
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        local hop="${trimmed%%.*}"
        local after="${trimmed#*.}"
        after="${after#|--}"
        { _fr_tok "$after"; _a=("${_FR_TOK[@]}"); }
        local k=0 j
        entry=$((entry + 1))
        result+="entry${entry}.hop ${hop}"$'\n'
        if [[ "${_a[0]}" =~ ^AS([0-9]+|\?+)$ && ${#_a[@]} -gt $(( ${#names[@]} + 1 )) ]]; then
            result+="entry${entry}.asn ${_a[0]}"$'\n'; k=1
        fi
        result+="entry${entry}.host ${_a[$k]}"$'\n'; k=$((k + 1))
        for ((j = 0; j < ${#names[@]}; j++)); do
            [[ -n "${_a[$((k + j))]:-}" ]] || continue
            result+="entry${entry}.${names[$j]} ${_a[$((k + j))]}"$'\n'
        done
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
