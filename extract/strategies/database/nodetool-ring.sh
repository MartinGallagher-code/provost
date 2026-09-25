#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: nodetool-ring
## Description: Extract ring token rows from `nodetool ring`
## Version: 1.0
## Priority: 20
## Sample: samples/nodetool-ring/basic.txt

# `nodetool ring` prints a "Datacenter:" banner, a "====" rule, an aligned
# header `Address  Rack  Status  State  Load  Owns  Token`, then one row per
# node. Load is "<num> <unit>" (two tokens). Emit ONE record per ring row keyed
# on the IPv4 address in the first column.

_nr_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"Datacenter:"* ]] || return 1
    [[ "$text" == *"Address"*"Rack"*"Status"*"State"* ]] || return 1
    [[ "$text" == *"Token"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line
    local -a t
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        { _fr_tok "$line"; t=("${_FR_TOK[@]}"); }
        [[ ${#t[@]} -eq 8 ]] || continue
        [[ "${t[0]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.address ${t[0]}"$'\n'
        result+="entry${entry}.rack ${t[1]}"$'\n'
        result+="entry${entry}.status ${t[2]}"$'\n'
        result+="entry${entry}.state ${t[3]}"$'\n'
        result+="entry${entry}.load $(_nr_san "${t[4]} ${t[5]}")"$'\n'
        result+="entry${entry}.owns ${t[6]}"$'\n'
        result+="entry${entry}.token ${t[7]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
