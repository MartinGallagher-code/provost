#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: ior
## Description: IOR (3.x/4.x) per-iteration results — one row per access per iteration, units in the column names
## Version: 1.0
## Priority: 20
## Sample: samples/ior/ior-4.0.0.txt

# IOR prints a run header (Began, Command line, Machine, Path, FS), an
# "Options:" block, then one "Results:" table per test:
#
#   access    bw(MiB/s)  IOPS       Latency(s)  block(KiB) xfer(KiB)  open(s)    wr/rd(s)   close(s)   total(s)   iter
#   ------    ---------  ----       ----------  ---------- ---------  --------   --------   --------   --------   ----
#   write     10246      10267      0.001508    1048576    1024.00    0.006969   1.60       0.046299   1.60       0
#   read      13442      13456      0.001111    1048576    1024.00    0.003215   1.22       0.022470   1.22       0
#   remove    -          -          -           -          -          -          -          -          0.014637   0
#
# and, at the end, a "Summary of all tests:" table (max/min/mean over the
# iterations, derivable from the rows) and "Finished". The generic fixed-width
# parse takes the Results table but runs on into the summary header, its rows
# and the Finished line. One record per Results row: test (1, 2, … for each
# "Results:" block, as an IOR script runs several), access, bw_mib_s, iops,
# latency_s, block_kib, xfer_kib, open_s, wr_rd_s, close_s, total_s, iter.
# A `-` cell (IOR 3.x's remove rows) is left out. Columns are matched by the
# header's names, so a version that adds or drops one keeps the rest right.

_ior_colname () {
    case "$1" in
        access) printf access ;; "bw(MiB/s)") printf bw_mib_s ;; "bw(MB/s)") printf bw_mb_s ;;
        IOPS) printf iops ;; "Latency(s)") printf latency_s ;; "block(KiB)") printf block_kib ;;
        "xfer(KiB)") printf xfer_kib ;; "open(s)") printf open_s ;; "wr/rd(s)") printf wr_rd_s ;;
        "close(s)") printf close_s ;; "total(s)") printf total_s ;; iter) printf iter ;;
        *) local v="${1//[^A-Za-z0-9]/_}"; while [[ "$v" == *__* ]]; do v="${v//__/_}"; done
           v="${v#_}"; v="${v%_}"; printf '%s' "$v" | tr 'A-Z' 'a-z' ;;
    esac
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="IOR Results table (access bw(MiB/s) IOPS ... iter)"
    [[ "$text" == *IOR-* ]] || return 1
    [[ "$text" =~ (^|$'\n')access[[:space:]]+bw\(Mi?B/s\)[[:space:]]+IOPS ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 test=0 line i
    local -a cols=() t=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" =~ ^access[[:space:]]+bw\( ]]; then
            { _fr_tok "$line"; cols=("${_FR_TOK[@]}"); }
            test=$((test + 1))
            continue
        fi
        [[ ${#cols[@]} -gt 0 ]] || continue
        # a data row: write/read/remove (any lowercase access word) + a cell per column
        [[ "$line" =~ ^[a-z]+[[:space:]] && "$line" != access* ]] || { [[ "$line" == "Summary of all tests"* ]] && cols=(); continue; }
        { _fr_tok "$line"; t=("${_FR_TOK[@]}"); }
        [[ ${#t[@]} -eq ${#cols[@]} ]] || continue
        [[ "${t[${#t[@]}-1]}" =~ ^[0-9]+$ ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.test ${test}"$'\n'
        for ((i = 0; i < ${#cols[@]}; i++)); do
            [[ "${t[i]}" == "-" ]] && continue
            result+="entry${entry}.$(_ior_colname "${cols[i]}") ${t[i]}"$'\n'
        done
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
