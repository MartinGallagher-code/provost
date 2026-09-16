#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: iperf-pivot
## Description: Extract the full-mesh throughput matrix from `iperf-orchestrator make-pivot` output (one row per measured source -> target cell)
## Version: 1.0
## Priority: 21
## Sample: samples/iperf-pivot/basic.txt

# `iperf-orchestrator make-pivot` prints a short prose preamble, then an ASCII
# throughput matrix, then optional trailing sections:
#
#   iperf2 full-mesh throughput (Mbps)
#   Run at:   2026-08-20 13:40:59 +0000
#   Mode:     parallel    Duration: 10s    Port: 5001    Parallel: 1    Hosts: 3
#   Rows = source (sender), Columns = target (receiver)
#   ...prose...
#
#             | 10.0.0.10 10.0.0.11 10.0.0.12
#   ----------+------------------------------
#   10.0.0.10 |         -   9440.00   3360.00
#   10.0.0.11 |   9200.00         -         -
#   10.0.0.12 |         -         -         -
#
#   Per-host incoming bandwidth (...):
#     10.0.0.11    9440.00 Mbps ( 1.180 GB/s)  ####...
#
#   Fleet aggregate bandwidth (sum of all directional flows): 22000.00 Mbps  (2.750 GB/s)
#     mean per-host throughput: ...
#
# The matrix is the data: one entry per measured cell. Cells reading '-' (no
# self-test / never measured) or '-(N)' (N attempts, none successful) carry no
# throughput, so they are SKIPPED rather than emitted with an empty value.
# The per-host bar chart and the prose preamble sentences are out of scope; the
# `Run at:` / `Mode:` header fields and the Fleet aggregate line are broadcast
# alongside the cells.

_iperfpiv_title='iperf2 full-mesh throughput (Mbps)'
_iperfpiv_rowscols='Rows = source (sender), Columns = target (receiver)'
_iperfpiv_re_runat='^Run at:[[:space:]]+(.+[^[:space:]])[[:space:]]*$'
_iperfpiv_re_mode='^Mode:[[:space:]]+([^[:space:]]+)'
_iperfpiv_re_duration='Duration:[[:space:]]+([^[:space:]]+)'
_iperfpiv_re_port='Port:[[:space:]]+([^[:space:]]+)'
_iperfpiv_re_parallel='Parallel:[[:space:]]+([^[:space:]]+)'
_iperfpiv_re_hosts='Hosts:[[:space:]]+([^[:space:]]+)'
# Matrix column header: nothing but whitespace left of the '|'.
_iperfpiv_re_matrix_hdr='^[[:space:]]*\|[[:space:]]*(.*)$'
# Matrix rule line: "----------+------------------------------".
_iperfpiv_re_matrix_rule='^[[:space:]]*-+\+-+[[:space:]]*$'
# Matrix data row: "<source> | <cell> <cell> ...".
_iperfpiv_re_matrix_row='^[[:space:]]*([^[:space:]|]+)[[:space:]]*\|[[:space:]]*(.*)$'
# A measured cell is a bare number; '-' and '-(N)' mean "no measurement".
_iperfpiv_re_cell_value='^[0-9]+(\.[0-9]+)?$'
_iperfpiv_re_fleet='^Fleet aggregate bandwidth[^:]*:[[:space:]]*([0-9.]+)[[:space:]]*Mbps([[:space:]]*\([[:space:]]*([0-9.]+)[[:space:]]*GB/s\))?'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # First line must be exactly the make-pivot title.
    local first="${text%%$'\n'*}"
    first="${first%$'\r'}"
    [[ "$first" == "$_iperfpiv_title" ]] || return 1
    [[ "$text" == *"$_iperfpiv_rowscols"* ]] || return 1
    _STRATEGY_CONFIDENCE=88
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local run_at="" mode="" duration_s="" port="" parallel="" n_hosts=""
    local fleet_mbps="" fleet_gbps=""
    local -a targets
    local state=0   # 0 = preamble, 1 = inside matrix, 2 = past matrix
    local line

    while IFS= read -r line; do
        if [[ $state -eq 0 ]]; then
            if [[ "$line" =~ $_iperfpiv_re_matrix_hdr ]]; then
                # Column header row; split the target names on whitespace.
                local hdr="${BASH_REMATCH[1]}"
                read -r -a targets <<< "$hdr"
                [[ ${#targets[@]} -eq 0 ]] && continue
                state=1
                continue
            fi
            if [[ "$line" =~ $_iperfpiv_re_runat ]]; then
                run_at="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ $_iperfpiv_re_mode ]]; then
                mode="${BASH_REMATCH[1]}"
                [[ "$line" =~ $_iperfpiv_re_duration ]] && duration_s="${BASH_REMATCH[1]%s}"
                [[ "$line" =~ $_iperfpiv_re_port ]] && port="${BASH_REMATCH[1]}"
                [[ "$line" =~ $_iperfpiv_re_parallel ]] && parallel="${BASH_REMATCH[1]}"
                [[ "$line" =~ $_iperfpiv_re_hosts ]] && n_hosts="${BASH_REMATCH[1]}"
            fi
            continue
        fi

        if [[ $state -eq 1 ]]; then
            # A blank line ends the matrix.
            if [[ -z "${line//[[:space:]]/}" ]]; then
                state=2
                continue
            fi
            [[ "$line" =~ $_iperfpiv_re_matrix_rule ]] && continue
            [[ "$line" =~ $_iperfpiv_re_matrix_row ]] || { state=2; continue; }

            local source="${BASH_REMATCH[1]}"
            local cells="${BASH_REMATCH[2]}"
            local -a cellv
            read -r -a cellv <<< "$cells"
            local idx=0 cell
            for cell in ${cellv[@]+"${cellv[@]}"}; do
                local target="${targets[$idx]:-}"
                idx=$((idx + 1))
                [[ -z "$target" ]] && continue
                # Skip unmeasured cells: '-' and '-(N)'.
                [[ "$cell" =~ $_iperfpiv_re_cell_value ]] || continue
                n=$((n + 1))
                local p="entry${n}."
                result+="${p}source ${source}"$'\n'
                result+="${p}target ${target}"$'\n'
                result+="${p}mbps ${cell}"$'\n'
            done
            continue
        fi

        # state 2: trailing sections; only the Fleet aggregate line is in scope.
        if [[ "$line" =~ $_iperfpiv_re_fleet ]]; then
            fleet_mbps="${BASH_REMATCH[1]}"
            fleet_gbps="${BASH_REMATCH[3]}"
        fi
    done <<< "$text"

    [[ -n "$run_at" ]] && result+="run_at ${run_at}"$'\n'
    [[ -n "$mode" ]] && result+="mode ${mode}"$'\n'
    [[ -n "$duration_s" ]] && result+="duration_s ${duration_s}"$'\n'
    [[ -n "$port" ]] && result+="port ${port}"$'\n'
    [[ -n "$parallel" ]] && result+="parallel ${parallel}"$'\n'
    [[ -n "$n_hosts" ]] && result+="n_hosts ${n_hosts}"$'\n'
    [[ -n "$fleet_mbps" ]] && result+="fleet_mbps ${fleet_mbps}"$'\n'
    [[ -n "$fleet_gbps" ]] && result+="fleet_gbps ${fleet_gbps}"$'\n'
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
