#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: restic
## Description: Extract snapshots from `restic snapshots` output (skips header rule + count footer)
## Version: 1.0
## Priority: 22
## Sample: samples/restic/basic.txt

# `restic snapshots` prints an "ID Time Host Tags Paths" header, a dashed rule,
# one row per snapshot, a second dashed rule, then an "N snapshots" footer. Only
# the rows between the two rules are data.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive restic header columns + a "snapshots" footer.
    [[ "$text" == *"ID"* && "$text" == *"Host"* && "$text" == *"Paths"* ]] || return 1
    [[ "$text" == *"snapshots"* ]] || return 1
    local line stripped
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        stripped="${line//-/}"
        if [[ -z "$stripped" && "$line" == *-* ]]; then
            _STRATEGY_CONFIDENCE=92
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 in_data=0 line stripped
    local -a t
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        stripped="${line//-/}"
        if [[ -z "$stripped" && "$line" == *-* ]]; then
            if [[ $in_data -eq 0 ]]; then in_data=1; else in_data=0; fi
            continue
        fi
        [[ $in_data -eq 1 ]] || continue
        [[ -z "$line" ]] && continue
        { _fr_tok "$line"; t=("${_FR_TOK[@]}"); }
        [[ ${#t[@]} -ge 6 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.id ${t[0]}"$'\n'
        result+="entry${entry}.date ${t[1]}"$'\n'
        result+="entry${entry}.time ${t[2]}"$'\n'
        result+="entry${entry}.host ${t[3]}"$'\n'
        result+="entry${entry}.tags ${t[4]}"$'\n'
        result+="entry${entry}.paths ${t[5]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
