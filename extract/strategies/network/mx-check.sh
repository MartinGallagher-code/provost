#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: mx-check
## Description: Extract the per-host offered-load table from `mx check` output (one row per host, matrix/fleet summary broadcast)
## Version: 1.0
## Priority: 22
## Sample: samples/mx-check/basic.txt

# `mx check` prints a one-line matrix summary, then a real aligned table of
# per-host packet/bandwidth figures, then a "fleet offered:" line and some
# free-form advisory prose (caps warning, worker-sizing note) that is out of
# scope here:
#   matrix matrix.csv: 3 hosts, 6 flows, 64 bytes out -> 64 bytes back, port 5300
#
#     host                        packets/s     out (wire)      in (wire)
#     10.0.0.10                   80.0 kpps      83.2 Mbps      83.2 Mbps
#     10.0.0.11                   80.0 kpps      83.2 Mbps      83.2 Mbps
#     10.0.0.12                   80.0 kpps      83.2 Mbps      83.2 Mbps
#
#     fleet offered: 120.0 kpps requests + the same rate in replies
#     no caps given -- pass --nic-gbps and/or --nic-mpps to check them
#
#     note: one agent worker process sustains roughly 200k packets/sec of
#           request+reply. `--workers auto` (the default) runs one per
#           core, so a host's own ceiling is about 200k x cores.
# One record per host row (entryN.*); the matrix/fleet line fields broadcast
# onto every row.

# Split $1 on runs of 2+ spaces into array MXCHK_SEG (a single interior space
# stays inside a segment — "out (wire)" is one header cell, not two).
_mxchk_split_wide () {
    local rest="$1" seg
    MXCHK_SEG=()
    rest="${rest#"${rest%%[![:space:]]*}"}"
    while [[ -n "$rest" ]]; do
        if [[ "$rest" =~ ^([^[:space:]]([^[:space:]]|[[:space:]][^[:space:]])*) ]]; then
            seg="${BASH_REMATCH[1]}"
        else
            seg="$rest"
        fi
        MXCHK_SEG+=("$seg")
        rest="${rest:${#seg}}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
    done
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    _is_json "$text" && return 1

    [[ "$text" =~ ^matrix[[:space:]]+[^[:space:]]+:.*hosts.*flows ]] || return 1

    local has_hdr=0 line t
    while IFS= read -r line; do
        t="${line#"${line%%[![:space:]]*}"}"
        if [[ "$t" == "host"[[:space:]]* && "$t" == *"packets/s"* ]]; then
            has_hdr=1
            break
        fi
    done <<< "$text"
    [[ $has_hdr -eq 1 ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line first=1 in_table=0 n=0

    local re_header='^matrix[[:space:]]+([^[:space:]]+):[[:space:]]+([0-9]+)[[:space:]]+hosts,[[:space:]]+([0-9]+)[[:space:]]+flows,[[:space:]]+(.+)[[:space:]]+out[[:space:]]+->[[:space:]]+(.+)[[:space:]]+back,[[:space:]]+port[[:space:]]+([0-9]+)[[:space:]]*$'

    local matrix_file="" host_count="" flow_count="" tx_size="" rx_size="" port="" fleet_offered=""

    while IFS= read -r line; do
        if [[ $first -eq 1 ]]; then
            first=0
            if [[ "$line" =~ $re_header ]]; then
                matrix_file="${BASH_REMATCH[1]}"
                host_count="${BASH_REMATCH[2]}"
                flow_count="${BASH_REMATCH[3]}"
                tx_size="${BASH_REMATCH[4]}"
                rx_size="${BASH_REMATCH[5]}"
                port="${BASH_REMATCH[6]}"
            fi
            continue
        fi

        [[ -z "${line//[[:space:]]/}" ]] && { in_table=0; continue; }
        local t="${line#"${line%%[![:space:]]*}"}"

        # Header row of the per-host table: enter table mode.
        if [[ $in_table -eq 0 && "$t" == "host"[[:space:]]* && "$t" == *"packets/s"* ]]; then
            in_table=1
            continue
        fi

        if [[ $in_table -eq 1 ]]; then
            _mxchk_split_wide "$t"
            if [[ ${#MXCHK_SEG[@]} -ge 4 ]]; then
                n=$((n + 1))
                local p="entry${n}."
                result+="${p}host ${MXCHK_SEG[0]}"$'\n'
                result+="${p}packets_per_sec ${MXCHK_SEG[1]}"$'\n'
                result+="${p}out_wire ${MXCHK_SEG[2]}"$'\n'
                result+="${p}in_wire ${MXCHK_SEG[3]}"$'\n'
                continue
            fi
            # A non-data line ends the table (e.g. "fleet offered:" line
            # reached without a blank separator).
            in_table=0
        fi

        case "$t" in
            "fleet offered:"*)
                fleet_offered="$t"
                ;;
        esac
    done <<< "$text"

    [[ -n "$matrix_file" ]] && result+="matrix_file ${matrix_file}"$'\n'
    [[ -n "$host_count" ]] && result+="host_count ${host_count}"$'\n'
    [[ -n "$flow_count" ]] && result+="flow_count ${flow_count}"$'\n'
    [[ -n "$tx_size" ]] && result+="tx_size ${tx_size}"$'\n'
    [[ -n "$rx_size" ]] && result+="rx_size ${rx_size}"$'\n'
    [[ -n "$port" ]] && result+="port ${port}"$'\n'
    [[ -n "$fleet_offered" ]] && result+="fleet_offered ${fleet_offered}"$'\n'
    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
