#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: hpl
## Description: HPL (High-Performance Linpack) results — one row per test with its residual check (HPL 2.x, HPCC's HPL section)
## Version: 1.0
## Priority: 20
## Sample: samples/hpl/hpcc-1.5.0.txt

# `xhpl` echoes its banner and HPL.dat parameters, then prints each test as a
# block with its OWN copy of the column header:
#
#   ================================================================================
#   T/V                N    NB     P     Q               Time                 Gflops
#   --------------------------------------------------------------------------------
#   WR11C2R4        2000    96     2     2               0.60              8.968e+00
#   HPL_pdgesv() start time Mon Nov  9 10:02:11 2026          (HPL 2.1 and later)
#
#   HPL_pdgesv() end time   Mon Nov  9 10:02:12 2026
#
#   --------------------------------------------------------------------------------
#   ||Ax-b||_oo/(eps*(||A||_oo*||x||_oo+||b||_oo)*N)=        0.0039802 ...... PASSED
#
# and a "Finished N tests" summary at the end. No generic parser keeps those
# rows: the header repeats per row, the parameter echo before them is a
# key/value block, and each row's residual check is on a line of its own.
# HPC Challenge (hpcc) embeds HPL 2.0 and prints the same blocks inside its
# "Begin of HPL section." ... "End of HPL section." markers.
#
# One record per test: tv (the encoded variant), matrix_n (N), nb, p, q, time_s, gflops,
# then the residual and its PASSED/FAILED check from the residual line, and
# the start and end times when this HPL prints them. Units go in the names
# (time_s; gflops is the unit).

_hpl_is_num () { [[ "$1" =~ ^[0-9]+(\.[0-9]*)?([eE][-+]?[0-9]+)?$ ]]; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="HPL result blocks (T/V N NB P Q Time Gflops)"
    [[ "$text" == *HPLinpack* ]] || return 1
    [[ "$text" =~ T/V[[:space:]]+N[[:space:]]+NB[[:space:]]+P[[:space:]]+Q[[:space:]]+Time[[:space:]]+Gflops ]] || return 1
    # at least one result row: an encoded variant (W + R/C + digits/letters) and six numbers
    [[ "$text" =~ (^|$'\n')W[RC][0-9A-Z]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9.]+[[:space:]]+[0-9.eE+-]+ ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line v
    local -a t=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        case "$line" in
            W[RC]*)
                { _fr_tok "$line"; t=("${_FR_TOK[@]}"); }
                [[ ${#t[@]} -eq 7 ]] || continue
                _hpl_is_num "${t[1]}" && _hpl_is_num "${t[5]}" && _hpl_is_num "${t[6]}" || continue
                entry=$((entry + 1))
                result+="entry${entry}.tv ${t[0]}"$'\n'
                result+="entry${entry}.matrix_n ${t[1]}"$'\n'
                result+="entry${entry}.nb ${t[2]}"$'\n'
                result+="entry${entry}.p ${t[3]}"$'\n'
                result+="entry${entry}.q ${t[4]}"$'\n'
                result+="entry${entry}.time_s ${t[5]}"$'\n'
                result+="entry${entry}.gflops ${t[6]}"$'\n'
                ;;
            "HPL_pdgesv() start time "*)
                [[ $entry -gt 0 ]] || continue
                v="${line#HPL_pdgesv() start time }"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
                result+="entry${entry}.start_time ${v}"$'\n'
                ;;
            "HPL_pdgesv() end time "*)
                [[ $entry -gt 0 ]] || continue
                v="${line#HPL_pdgesv() end time }"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
                result+="entry${entry}.end_time ${v}"$'\n'
                ;;
            "||Ax-b||"*=*)
                [[ $entry -gt 0 ]] || continue
                { _fr_tok "${line#*=}"; t=("${_FR_TOK[@]}"); }
                [[ ${#t[@]} -ge 1 ]] && result+="entry${entry}.residual ${t[0]}"$'\n'
                [[ "${t[${#t[@]}-1]}" == PASSED || "${t[${#t[@]}-1]}" == FAILED ]] &&
                    result+="entry${entry}.check ${t[${#t[@]}-1]}"$'\n'
                ;;
        esac
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
