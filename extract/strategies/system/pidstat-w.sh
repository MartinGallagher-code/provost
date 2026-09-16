#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: pidstat-w
## Description: pidstat -w per-process context-switch stats → one tidy row per process
## Version: 1.0
## Priority: 22
## Sample: samples/pidstat-w/basic.txt

# `pidstat -w` prints a "Linux ..." banner, a blank line, a
# "#  Time UID PID cswch/s nvcswch/s Command" header, then one row per process,
# optionally an "Average:" footer. Each process row begins with an HH:MM:SS
# timestamp — that alone distinguishes it from banner/header/Average lines.

_pidstat_w_is_row () {
    [[ "$1" =~ ^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"cswch/s"* && "$text" == *"nvcswch/s"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local toks
    while IFS= read -r line; do
        toks=(); read -ra toks <<< "$line"
        [[ ${#toks[@]} -ge 6 ]] || continue
        _pidstat_w_is_row "${toks[0]}" || continue
        local cmd="${toks[*]:5}"
        entry=$((entry + 1))
        result+="entry${entry}.time ${toks[0]}"$'\n'
        result+="entry${entry}.uid ${toks[1]}"$'\n'
        result+="entry${entry}.pid ${toks[2]}"$'\n'
        result+="entry${entry}.cswch_s ${toks[3]}"$'\n'
        result+="entry${entry}.nvcswch_s ${toks[4]}"$'\n'
        result+="entry${entry}.command ${cmd}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
