#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: powertop
## Description: powertop tunable/usage table → one tidy row per process (usage, events, category, description)
## Version: 1.0
## Priority: 20
## Sample: samples/powertop/basic.txt

# powertop's overview prints a discharge/summary preamble then an aligned table:
#     Usage       Events/s    Category       Description
#     45.2 ms/s    142.1       Process        /usr/lib/postgresql/postgres
# The Usage column is a number + unit ("45.2 ms/s"), so plain whitespace splitting
# over-counts columns; parse positionally instead. Tidied to one row per entry.

_pt_is_header () {
    [[ "$1" == *"Events/s"* && "$1" == *"Category"* ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line seen_hdr=0 seen_row=0
    while IFS= read -r line; do
        if [[ $seen_hdr -eq 0 ]]; then
            _pt_is_header "$line" && seen_hdr=1
        else
            [[ -n "${line//[[:space:]]/}" ]] && seen_row=1
        fi
    done <<< "$text"
    if [[ $seen_hdr -eq 1 && $seen_row -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line past=0
    while IFS= read -r line; do
        if [[ $past -eq 0 ]]; then
            _pt_is_header "$line" && past=1
            continue
        fi
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local toks; toks=(); read -ra toks <<< "$line"
        local n=${#toks[@]}
        # usage(value unit) events category description...  -> need >= 4 tokens
        [[ $n -ge 4 ]] || continue
        local usage="${toks[0]}_${toks[1]}"
        local events="${toks[2]}"
        local category="${toks[3]}"
        local desc="" i
        for ((i = 4; i < n; i++)); do
            [[ -n "$desc" ]] && desc+="_"
            desc+="${toks[$i]}"
        done
        [[ -z "$desc" ]] && desc="-"
        entry=$((entry + 1))
        result+="entry${entry}.usage ${usage}"$'\n'
        result+="entry${entry}.events ${events}"$'\n'
        result+="entry${entry}.category ${category}"$'\n'
        result+="entry${entry}.description ${desc}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
