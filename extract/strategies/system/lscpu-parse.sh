#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: lscpu-parse
## Description: Extract per-CPU topology rows from lscpu -p parsable CSV output
## Version: 1.0
## Priority: 26
## Sample: samples/lscpu-parse/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # lscpu -p: "#"-comment preamble then rows like "0,0,0,0,,0,0,0,0"
    # (the empty 5th field / double comma is distinctive).
    local rows=0 line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue
        # A CPU row starts with an integer, is comma-separated, and contains
        # the empty-field ",," produced by lscpu -p.
        if [[ "$line" =~ ^[0-9]+, ]] && [[ "$line" == *",,"* ]]; then
            rows=$((rows + 1))
        fi
    done <<< "$text"
    if [[ $rows -ge 2 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue
        [[ "$line" =~ ^[0-9]+, ]] || continue

        IFS=',' read -ra c <<< "$line"
        # c[0]=cpu c[1]=core c[2]=socket c[3]=node c[4]=(empty) c[5]=L1d c[6]=L1i c[7]=L2 c[8]=L3
        [[ ${#c[@]} -ge 9 ]] || continue

        entry=$((entry + 1))
        result+="entry${entry}.cpu ${c[0]}"$'\n'
        result+="entry${entry}.core ${c[1]}"$'\n'
        result+="entry${entry}.socket ${c[2]}"$'\n'
        result+="entry${entry}.node ${c[3]}"$'\n'
        result+="entry${entry}.l1d ${c[5]}"$'\n'
        result+="entry${entry}.l1i ${c[6]}"$'\n'
        result+="entry${entry}.l2 ${c[7]}"$'\n'
        result+="entry${entry}.l3 ${c[8]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
