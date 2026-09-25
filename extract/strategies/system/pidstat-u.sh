#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: pidstat-u
## Description: pidstat -u per-process CPU stats → one tidy row per process
## Version: 1.0
## Priority: 22
## Sample: samples/pidstat-u/basic.txt

# `pidstat -u` prints a "Linux ..." banner, a blank line, a
# "#  Time UID PID %usr %system %guest %wait %CPU CPU Command" header, then one
# row per process, optionally an "Average:" footer. Each process row begins with
# an HH:MM:SS timestamp — that alone distinguishes it from banner/header/Average.

_pidstat_u_is_row () {
    [[ "$1" =~ ^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"%usr"* && "$text" == *"%guest"* && "$text" == *"%wait"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local toks
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        toks=(); { _fr_tok "$line"; toks=("${_FR_TOK[@]}"); }
        [[ ${#toks[@]} -ge 10 ]] || continue
        _pidstat_u_is_row "${toks[0]}" || continue
        local cmd="${toks[*]:9}"
        entry=$((entry + 1))
        result+="entry${entry}.time ${toks[0]}"$'\n'
        result+="entry${entry}.uid ${toks[1]}"$'\n'
        result+="entry${entry}.pid ${toks[2]}"$'\n'
        result+="entry${entry}.pct_usr ${toks[3]}"$'\n'
        result+="entry${entry}.pct_system ${toks[4]}"$'\n'
        result+="entry${entry}.pct_guest ${toks[5]}"$'\n'
        result+="entry${entry}.pct_wait ${toks[6]}"$'\n'
        result+="entry${entry}.pct_cpu ${toks[7]}"$'\n'
        result+="entry${entry}.cpu ${toks[8]}"$'\n'
        result+="entry${entry}.command ${cmd}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
