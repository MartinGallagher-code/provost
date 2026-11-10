#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: hpcg
## Description: HPCG 3.x results file (HPCG-Benchmark_3.x_*.txt) — one wide record per run, every key kept, the rating split out
## Version: 1.0
## Priority: 20
## Sample: samples/hpcg/hpcg-3.1.txt

# HPCG 3.1 writes its result as `Section::Sub::Key=value` lines, a bare
# `Section=` line opening each section and `##### Title #####=` banners:
#
#   HPCG-Benchmark
#   version=3.1
#   Machine Summary::Distributed Processes=16
#   Multigrid Information::Coarse Grids::Grid Level=1
#   Multigrid Information::Coarse Grids::Number of Equations=2249728
#   ...
#   Final Summary::HPCG result is VALID with a GFLOP/s rating of=8.92472
#
# (src/ReportResults.cpp, src/OutputFile.cpp.) The generic `equals` parser
# claims it but drops every key over 50 characters, and with them the
# official rating line. One record, a column per key: the path in lower
# snake case joined with `.` (units stay in the name:
# memory_use_information.total_memory_used_for_data_gbytes); the coarse-grid
# blocks, which repeat their keys per level, get `level_N.`
# (multigrid_information.coarse_grids.level_1.number_of_equations). The
# verdict line becomes final_summary.result (VALID / INVALID) and
# final_summary.gflops_rating.

_hpcg_key () {
    local k="$1"
    k="$(printf '%s' "$k" | tr 'A-Z' 'a-z')"
    k="${k//./_}"                                  # `HPCG 2.4 rating`: a dot in a name is no path step
    k="${k//::/.}"
    k="${k//[^a-z0-9.]/_}"
    while [[ "$k" == *__* ]]; do k="${k//__/_}"; done
    k="${k//_./.}"; k="${k//._/.}"; k="${k#_}"; k="${k%_}"
    printf '%s' "$k"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="HPCG results file (HPCG-Benchmark, Section::Key=value)"
    [[ "$text" == HPCG-Benchmark* ]] || return 1
    [[ "$text" == *"::"*=* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" line key val path sect level="" lsect="" n=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"; val="${line#*=}"
        val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
        [[ -z "$val" ]] && continue                      # a section opener or a banner
        [[ "$key" == "#"* ]] && continue
        sect="${key%::*}"; [[ "$sect" == "$key" ]] && sect=""
        if [[ "$key" == *"::Grid Level" ]]; then
            level="$val"; lsect="$sect"; continue
        fi
        [[ "$sect" != "$lsect" ]] && level=""
        case "$key" in
            "Final Summary::HPCG result is VALID with a GFLOP/s rating of")
                result+="final_summary.result VALID"$'\n'
                result+="final_summary.gflops_rating ${val}"$'\n'; n=$((n + 2)); continue ;;
            "Final Summary::HPCG result is")
                result+="final_summary.result ${val%.}"$'\n'; n=$((n + 1)); continue ;;
        esac
        if [[ -n "$level" ]]; then
            path="$(_hpcg_key "$sect").level_${level}.$(_hpcg_key "${key##*::}")"
        else
            path="$(_hpcg_key "$key")"
        fi
        result+="${path} ${val}"$'\n'; n=$((n + 1))
    done
    [[ $n -gt 0 ]] && echo "$result"
}
