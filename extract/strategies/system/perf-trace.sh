#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: perf-trace
## Description: perf trace -s syscall summary table → one tidy row per syscall
## Version: 1.0
## Priority: 22
## Sample: samples/perf-trace/basic.txt

# `perf trace -s` prints a "Summary of events:" banner, a per-thread line
# (e.g. "mysqld (1843), 88213 events, 42.1%"), a
# "syscall calls errors total (msec) min (msec) avg (msec) max (msec) stddev (%)"
# header, then one row per syscall. A syscall row has 8 whitespace fields whose
# second field (calls) is an integer — that distinguishes it from the banner,
# the thread line, and the parenthesised header.

_perf_trace_is_row () {
    # $1 = field count, $2 = the calls token
    [[ "$1" -eq 8 && "$2" =~ ^[0-9]+$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Summary of events:"* && "$text" == *"stddev"* ]] || return 1
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
        _perf_trace_is_row "${#toks[@]}" "${toks[1]:-}" || continue
        entry=$((entry + 1))
        result+="entry${entry}.syscall ${toks[0]}"$'\n'
        result+="entry${entry}.calls ${toks[1]}"$'\n'
        result+="entry${entry}.errors ${toks[2]}"$'\n'
        result+="entry${entry}.total_msec ${toks[3]}"$'\n'
        result+="entry${entry}.min_msec ${toks[4]}"$'\n'
        result+="entry${entry}.avg_msec ${toks[5]}"$'\n'
        result+="entry${entry}.max_msec ${toks[6]}"$'\n'
        result+="entry${entry}.stddev_pct ${toks[7]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
