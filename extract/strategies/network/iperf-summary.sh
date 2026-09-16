#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: iperf-summary
## Description: Extract the slowest-direction list and throughput stats from `iperf-orchestrator results-summary` output
## Version: 1.0
## Priority: 21
## Sample: samples/iperf-summary/basic.txt

# `iperf-orchestrator results-summary` prints a one-line header, a fixed block
# of throughput percentiles, then a "Slowest N" list and a prose "What next:"
# section:
#
#   Throughput summary across 3 measured directions (0 errored/missing)
#     min:       3360.00 Mbps
#     P50:       9200.00 Mbps
#     mean:      7333.33 Mbps
#     P95:       9440.00 Mbps
#     max:       9440.00 Mbps
#
#   Slowest 5 (source -> target):
#        3360.00  10.0.0.10 -> 10.0.0.12
#        9200.00  10.0.0.11 -> 10.0.0.10
#
#   What next:
#     - <wrapped prose advice>
#
# The "Slowest" list is the data (one entry per direction); the header counts
# and the percentile block are broadcast alongside it. The "What next:" prose
# bullets are out of scope.

_iperfsum_re_header='^Throughput summary across ([0-9]+) measured directions([[:space:]]*\(([0-9]+) errored)?'
_iperfsum_re_stat='^[[:space:]]*(min|P50|mean|P95|max):[[:space:]]+([0-9.]+)[[:space:]]*Mbps[[:space:]]*$'
_iperfsum_re_slowest_hdr='^Slowest[[:space:]]'
_iperfsum_re_entry='^[[:space:]]+([0-9]+(\.[0-9]+)?)[[:space:]]+([^[:space:]]+)[[:space:]]+->[[:space:]]+([^[:space:]]+)[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local first="${text%%$'\n'*}"
    first="${first%$'\r'}"
    [[ "$first" =~ $_iperfsum_re_header ]] || return 1
    # A "Slowest ..." section header must be present.
    local line found=0
    while IFS= read -r line; do
        if [[ "$line" =~ $_iperfsum_re_slowest_hdr ]]; then found=1; break; fi
    done <<< "$text"
    [[ $found -eq 1 ]] || return 1
    _STRATEGY_CONFIDENCE=88
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local n_directions="" n_errored=""
    local min_mbps="" p50_mbps="" mean_mbps="" p95_mbps="" max_mbps=""
    local state=0   # 0 = header/stats, 1 = inside Slowest list, 2 = past it
    local line

    while IFS= read -r line; do
        if [[ $state -eq 0 ]]; then
            if [[ "$line" =~ $_iperfsum_re_slowest_hdr ]]; then
                state=1
                continue
            fi
            if [[ "$line" =~ $_iperfsum_re_header ]]; then
                n_directions="${BASH_REMATCH[1]}"
                n_errored="${BASH_REMATCH[3]}"
            elif [[ "$line" =~ $_iperfsum_re_stat ]]; then
                case "${BASH_REMATCH[1]}" in
                    min)  min_mbps="${BASH_REMATCH[2]}" ;;
                    P50)  p50_mbps="${BASH_REMATCH[2]}" ;;
                    mean) mean_mbps="${BASH_REMATCH[2]}" ;;
                    P95)  p95_mbps="${BASH_REMATCH[2]}" ;;
                    max)  max_mbps="${BASH_REMATCH[2]}" ;;
                esac
            fi
            continue
        fi

        if [[ $state -eq 1 ]]; then
            # A blank line ends the list; the "What next:" prose follows.
            if [[ -z "${line//[[:space:]]/}" ]]; then
                state=2
                continue
            fi
            [[ "$line" =~ $_iperfsum_re_entry ]] || continue
            n=$((n + 1))
            local p="entry${n}."
            result+="${p}mbps ${BASH_REMATCH[1]}"$'\n'
            result+="${p}source ${BASH_REMATCH[3]}"$'\n'
            result+="${p}target ${BASH_REMATCH[4]}"$'\n'
        fi
        # state 2: prose advice, out of scope.
    done <<< "$text"

    [[ -n "$n_directions" ]] && result+="n_directions ${n_directions}"$'\n'
    [[ -n "$n_errored" ]] && result+="n_errored ${n_errored}"$'\n'
    [[ -n "$min_mbps" ]] && result+="min_mbps ${min_mbps}"$'\n'
    [[ -n "$p50_mbps" ]] && result+="p50_mbps ${p50_mbps}"$'\n'
    [[ -n "$mean_mbps" ]] && result+="mean_mbps ${mean_mbps}"$'\n'
    [[ -n "$p95_mbps" ]] && result+="p95_mbps ${p95_mbps}"$'\n'
    [[ -n "$max_mbps" ]] && result+="max_mbps ${max_mbps}"$'\n'
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
