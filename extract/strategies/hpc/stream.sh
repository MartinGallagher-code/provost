#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: stream
## Description: STREAM memory-bandwidth results (stream.c 5.x) — one row per kernel, from the full printout
## Version: 1.0
## Priority: 20
## Sample: samples/stream/full-omp.txt

# What `./stream` prints is mostly prose around a four-row table:
#
#   -------------------------------------------------------------
#   STREAM version $Revision: 5.10 $
#   ...
#   Array size = 80000000 (elements), Offset = 0 (elements)
#   ...
#   Number of Threads counted = 16              (OpenMP builds)
#   ...
#   Function    Best Rate MB/s  Avg time     Min time     Max time
#   Copy:           98211.3     0.013204     0.013033     0.013491
#   Scale:          97032.6     0.013362     0.013191     0.013620
#   Add:           104715.9     0.018567     0.018335     0.018893
#   Triad:         105102.4     0.018519     0.018268     0.018840
#   -------------------------------------------------------------
#   Solution Validates: avg error less than 1.000000e-13 on all three arrays
#
# The table alone tidies through aligned-columns (the corpus's
# stream-benchmark), but the whole printout, which is what a run captures,
# reads as prose to every generic parser. One record per kernel: function,
# best_rate_mb_s, avg_time_s, min_time_s, max_time_s, with the run's
# array_size (elements), threads (when printed) and validation (validates /
# failed) carried onto each row.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="STREAM printout (Function / Best Rate MB/s table)"
    [[ "$text" == *"Function    Best Rate MB/s"* ]] || return 1
    [[ "$text" == *"Triad:"* ]] || return 1
    # The bare table (no STREAM banner) is aligned-columns' already; claim the
    # printout only when the prose around it is there too.
    [[ "$text" == *"STREAM version"* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line size="" threads="" valid="" fn
    local -a t=() rows=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        case "$line" in
            "Array size = "*)
                { _fr_tok "${line#Array size = }"; t=("${_FR_TOK[@]}"); }
                size="${t[0]}" ;;
            "Number of Threads counted = "*)
                threads="${line#Number of Threads counted = }"; threads="${threads%%[![:digit:]]*}" ;;
            "Number of Threads requested = "*)
                [[ -z "$threads" ]] && { threads="${line#Number of Threads requested = }"; threads="${threads%%[![:digit:]]*}"; } ;;
            "Solution Validates"*) valid="validates" ;;
            "Failed Validation"*) valid="failed" ;;
            Copy:*|Scale:*|Add:*|Triad:*)
                { _fr_tok "$line"; t=("${_FR_TOK[@]}"); }
                [[ ${#t[@]} -eq 5 && "${t[1]}" =~ ^[0-9.]+$ ]] || continue
                rows+=("$line") ;;
        esac
    done
    for line in "${rows[@]}"; do
        { _fr_tok "$line"; t=("${_FR_TOK[@]}"); }
        entry=$((entry + 1)); fn="${t[0]%:}"
        result+="entry${entry}.function ${fn}"$'\n'
        result+="entry${entry}.best_rate_mb_s ${t[1]}"$'\n'
        result+="entry${entry}.avg_time_s ${t[2]}"$'\n'
        result+="entry${entry}.min_time_s ${t[3]}"$'\n'
        result+="entry${entry}.max_time_s ${t[4]}"$'\n'
        [[ -n "$size" ]] && result+="entry${entry}.array_size ${size}"$'\n'
        [[ -n "$threads" ]] && result+="entry${entry}.threads ${threads}"$'\n'
        [[ -n "$valid" ]] && result+="entry${entry}.validation ${valid}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
