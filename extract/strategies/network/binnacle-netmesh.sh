#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: binnacle-netmesh
## Description: Extract the worst-pairs latency table and summary stats from `netmesh summarize` (binnacle) output
## Version: 1.0
## Priority: 20
## Sample: samples/binnacle-netmesh/basic.txt

# `netmesh summarize` (binnacle's mesh-latency diagnostic) prints a one-line
# header, a BASELINE/JITTER/LOSS/PATH MTU summary block, then a "WORST PAIRS"
# table:
#   netmesh summarize -- 5 hosts, 20 measured pairs, reports span 30s
#     ...
#   WORST PAIRS (of 20, ranked by p99)
#     web03 -> db01   p50 1.9ms  p99 8.4ms  jitter 640us  loss 0.9% (fwd 0.9%)
# followed by ASYMMETRY / PATH MTU / WHAT TO DO NEXT prose sections that are
# out of scope for this strategy.

_netmesh_re_header='^netmesh[[:space:]]+summarize[[:space:]]+--[[:space:]]+([0-9]+)[[:space:]]+hosts,[[:space:]]+([0-9]+)[[:space:]]+measured[[:space:]]+pairs,[[:space:]]+reports[[:space:]]+span[[:space:]]+([^[:space:]]+)'
_netmesh_re_baseline='BASELINE[[:space:]]+p50[[:space:]]+([^[:space:]]+)[[:space:]]+across[[:space:]]+all[[:space:]]+pairs[[:space:]]+worst[[:space:]]+pair[[:space:]]+p50[[:space:]]+([^[:space:]]+)'
_netmesh_re_jitter='JITTER[[:space:]]+median[[:space:]]+([^[:space:]]+)[[:space:]]+worst[[:space:]]+pair[[:space:]]+([^[:space:]]+)'
_netmesh_re_loss='LOSS[[:space:]]+([0-9.]+)%[[:space:]]+overall'
_netmesh_re_worst_hdr='WORST[[:space:]]+PAIRS'
_netmesh_re_stop='^[[:space:]]*(ASYMMETRY|PATH MTU|WHAT TO DO NEXT)[[:space:]]*$'
_netmesh_re_pair='^[[:space:]]*([^[:space:]]+)[[:space:]]+->[[:space:]]+([^[:space:]]+)[[:space:]]+p50[[:space:]]+([^[:space:]]+)[[:space:]]+p99[[:space:]]+([^[:space:]]+)[[:space:]]+jitter[[:space:]]+([^[:space:]]+)[[:space:]]+loss[[:space:]]+([0-9.]+)%([[:space:]]*\(([^)]*)\))?[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    [[ "$text" =~ (^|$'\n')netmesh[[:space:]]+summarize[[:space:]]+-- ]] || return 1
    [[ "$text" =~ $_netmesh_re_worst_hdr ]] || return 1
    _STRATEGY_CONFIDENCE=90
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local host_count="" pair_count="" span=""
    local baseline_p50="" baseline_worst_p50=""
    local jitter_median="" jitter_worst=""
    local loss_overall_pct=""
    local state=0   # 0 = before WORST PAIRS table, 1 = inside it, 2 = stopped

    while IFS= read -r line; do
        if [[ $state -eq 0 ]]; then
            if [[ "$line" =~ $_netmesh_re_header ]]; then
                host_count="${BASH_REMATCH[1]}"
                pair_count="${BASH_REMATCH[2]}"
                span="${BASH_REMATCH[3]}"
            elif [[ "$line" =~ $_netmesh_re_baseline ]]; then
                baseline_p50="${BASH_REMATCH[1]}"
                baseline_worst_p50="${BASH_REMATCH[2]}"
            elif [[ "$line" =~ $_netmesh_re_jitter ]]; then
                jitter_median="${BASH_REMATCH[1]}"
                jitter_worst="${BASH_REMATCH[2]}"
            elif [[ "$line" =~ $_netmesh_re_loss ]]; then
                loss_overall_pct="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ $_netmesh_re_worst_hdr ]]; then
                state=1
            fi
            continue
        fi

        if [[ $state -eq 1 ]]; then
            if [[ "$line" =~ $_netmesh_re_stop ]]; then
                state=2
                continue
            fi
            [[ "$line" =~ $_netmesh_re_pair ]] || continue

            n=$((n + 1))
            local p="entry${n}."
            result+="${p}src ${BASH_REMATCH[1]}"$'\n'
            result+="${p}dst ${BASH_REMATCH[2]}"$'\n'
            result+="${p}p50 ${BASH_REMATCH[3]}"$'\n'
            result+="${p}p99 ${BASH_REMATCH[4]}"$'\n'
            result+="${p}jitter ${BASH_REMATCH[5]}"$'\n'
            result+="${p}loss_pct ${BASH_REMATCH[6]}"$'\n'
            [[ -n "${BASH_REMATCH[8]}" ]] && result+="${p}loss_detail ${BASH_REMATCH[8]}"$'\n'
        fi
        # state 2: past the table, ignore everything else.
    done <<< "$text"

    [[ -n "$host_count" ]] && result+="host_count ${host_count}"$'\n'
    [[ -n "$pair_count" ]] && result+="pair_count ${pair_count}"$'\n'
    [[ -n "$span" ]] && result+="span ${span}"$'\n'
    [[ -n "$baseline_p50" ]] && result+="baseline_p50 ${baseline_p50}"$'\n'
    [[ -n "$baseline_worst_p50" ]] && result+="baseline_worst_p50 ${baseline_worst_p50}"$'\n'
    [[ -n "$jitter_median" ]] && result+="jitter_median ${jitter_median}"$'\n'
    [[ -n "$jitter_worst" ]] && result+="jitter_worst ${jitter_worst}"$'\n'
    [[ -n "$loss_overall_pct" ]] && result+="loss_overall_pct ${loss_overall_pct}"$'\n'
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
