#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: pidstat-r
## Description: pidstat -r per-process memory stats → one tidy row per process
## Version: 1.0
## Priority: 22
## Sample: samples/pidstat-r/basic.txt

# `pidstat -r` prints a "Linux ..." banner, a blank line, a
# "#  Time UID PID minflt/s majflt/s VSZ RSS %MEM Command" header, then one row
# per process (time-stamped), optionally an "Average:" footer. Each process row
# begins with an HH:MM:SS timestamp — that alone distinguishes it from the
# banner/header/Average lines, so we emit exactly one record per process.

_pidstat_r_is_row () {
    [[ "$1" =~ ^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"minflt/s"* && "$text" == *"majflt/s"* && "$text" == *"%MEM"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local toks
    while IFS= read -r line; do
        toks=(); read -ra toks <<< "$line"
        [[ ${#toks[@]} -ge 9 ]] || continue
        _pidstat_r_is_row "${toks[0]}" || continue
        local cmd="${toks[*]:8}"
        entry=$((entry + 1))
        result+="entry${entry}.time ${toks[0]}"$'\n'
        result+="entry${entry}.uid ${toks[1]}"$'\n'
        result+="entry${entry}.pid ${toks[2]}"$'\n'
        result+="entry${entry}.minflt_s ${toks[3]}"$'\n'
        result+="entry${entry}.majflt_s ${toks[4]}"$'\n'
        result+="entry${entry}.vsz ${toks[5]}"$'\n'
        result+="entry${entry}.rss ${toks[6]}"$'\n'
        result+="entry${entry}.pct_mem ${toks[7]}"$'\n'
        result+="entry${entry}.command ${cmd}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
