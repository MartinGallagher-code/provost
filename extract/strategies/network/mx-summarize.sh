#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: mx-summarize
## Description: Extract the fixed metric block from `mx summarize` output (one row of requests/delivered/replies/target/total/loss/rtt fields)
## Version: 1.0
## Priority: 22
## Sample: samples/mx-summarize/basic.txt

# `mx summarize` prints one header line plus a FIXED set of one-line-per-metric
# rows, always in this order:
#   mx summarize -- last 60s, 12 hosts, 132 flows, 64 bytes out -> 64 bytes back
#
#     REQUESTS       2.640 Mpps       2.75 Gbps wire       1.35 Gbps payload
#     DELIVERED      2.601 Mpps    98.52% of what was sent
#     REPLIES        2.598 Mpps       2.71 Gbps wire       1.33 Gbps payload
#     TARGET         2.640 Mpps   100.0% achieved
#     TOTAL          5.238 Mpps       5.46 Gbps wire, both directions
#     LOSS               1.59%   round trip (1.48% forward, 0.11% on the way back)
#     RTT       avg 240us over all flows; worst flow p50 190us  p99 4.1ms  max 31ms
#
# There is never more than one block per invocation, so this is a single-record
# (plain field, no entryN.*) extraction — the tidy melt renders it as one wide
# row. Each metric's free-text value is kept as its own raw string rather than
# split into numbers/units, since the sub-shapes vary metric to metric.

# Split $1 on runs of 2+ spaces into array MXSUM_SEG (segments trimmed of
# surrounding whitespace; a single interior space stays part of a segment, so
# "2.75 Gbps wire" stays one segment while the 2+-space gaps after it start a
# new one).
_mxsum_split_wide () {
    local rest="$1" seg
    MXSUM_SEG=()
    rest="${rest#"${rest%%[![:space:]]*}"}"
    while [[ -n "$rest" ]]; do
        if [[ "$rest" =~ ^([^[:space:]]([^[:space:]]|[[:space:]][^[:space:]])*) ]]; then
            seg="${BASH_REMATCH[1]}"
        else
            seg="$rest"
        fi
        MXSUM_SEG+=("$seg")
        rest="${rest:${#seg}}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
    done
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    _is_json "$text" && return 1

    [[ "$text" == "mx summarize --"* ]] || return 1
    [[ "$text" =~ (^|$'\n')"  REQUESTS" ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line first=1

    local re_header='^mx summarize --[[:space:]]+(.+),[[:space:]]+([0-9]+)[[:space:]]+hosts,[[:space:]]+([0-9]+)[[:space:]]+flows,[[:space:]]+(.+)[[:space:]]+out[[:space:]]+->[[:space:]]+(.+)[[:space:]]+back[[:space:]]*$'
    local re_rtt='avg[[:space:]]+([^[:space:]]+).*p50[[:space:]]+([^[:space:]]+)[[:space:]]+p99[[:space:]]+([^[:space:]]+)[[:space:]]+max[[:space:]]+([^[:space:]]+)'

    while IFS= read -r line; do
        if [[ $first -eq 1 ]]; then
            first=0
            if [[ "$line" =~ $re_header ]]; then
                result+="window ${BASH_REMATCH[1]}"$'\n'
                result+="host_count ${BASH_REMATCH[2]}"$'\n'
                result+="flow_count ${BASH_REMATCH[3]}"$'\n'
                result+="tx_size ${BASH_REMATCH[4]}"$'\n'
                result+="rx_size ${BASH_REMATCH[5]}"$'\n'
            fi
            continue
        fi

        [[ -z "${line//[[:space:]]/}" ]] && continue
        local t="${line#"${line%%[![:space:]]*}"}"

        case "$t" in
            REQUESTS" "*)
                _mxsum_split_wide "${t#REQUESTS}"
                [[ -n "${MXSUM_SEG[0]:-}" ]] && result+="requests_pps ${MXSUM_SEG[0]}"$'\n'
                [[ -n "${MXSUM_SEG[1]:-}" ]] && result+="requests_wire ${MXSUM_SEG[1]}"$'\n'
                [[ -n "${MXSUM_SEG[2]:-}" ]] && result+="requests_payload ${MXSUM_SEG[2]}"$'\n'
                ;;
            DELIVERED" "*)
                _mxsum_split_wide "${t#DELIVERED}"
                [[ -n "${MXSUM_SEG[0]:-}" ]] && result+="delivered_pps ${MXSUM_SEG[0]}"$'\n'
                [[ -n "${MXSUM_SEG[1]:-}" ]] && result+="delivered_pct ${MXSUM_SEG[1]}"$'\n'
                ;;
            REPLIES" "*)
                _mxsum_split_wide "${t#REPLIES}"
                [[ -n "${MXSUM_SEG[0]:-}" ]] && result+="replies_pps ${MXSUM_SEG[0]}"$'\n'
                [[ -n "${MXSUM_SEG[1]:-}" ]] && result+="replies_wire ${MXSUM_SEG[1]}"$'\n'
                [[ -n "${MXSUM_SEG[2]:-}" ]] && result+="replies_payload ${MXSUM_SEG[2]}"$'\n'
                ;;
            TARGET" "*)
                _mxsum_split_wide "${t#TARGET}"
                [[ -n "${MXSUM_SEG[0]:-}" ]] && result+="target_pps ${MXSUM_SEG[0]}"$'\n'
                [[ -n "${MXSUM_SEG[1]:-}" ]] && result+="target_pct ${MXSUM_SEG[1]}"$'\n'
                ;;
            TOTAL" "*)
                _mxsum_split_wide "${t#TOTAL}"
                [[ -n "${MXSUM_SEG[0]:-}" ]] && result+="total_pps ${MXSUM_SEG[0]}"$'\n'
                [[ -n "${MXSUM_SEG[1]:-}" ]] && result+="total_wire ${MXSUM_SEG[1]}"$'\n'
                ;;
            LOSS" "*)
                _mxsum_split_wide "${t#LOSS}"
                [[ -n "${MXSUM_SEG[0]:-}" ]] && result+="loss_pct ${MXSUM_SEG[0]}"$'\n'
                if [[ ${#MXSUM_SEG[@]} -gt 1 ]]; then
                    local rest="${t#LOSS}"
                    rest="${rest#"${rest%%[![:space:]]*}"}"
                    rest="${rest#"${MXSUM_SEG[0]}"}"
                    rest="${rest#"${rest%%[![:space:]]*}"}"
                    result+="loss_detail ${rest}"$'\n'
                fi
                ;;
            RTT" "*)
                if [[ "$t" =~ $re_rtt ]]; then
                    result+="rtt_avg ${BASH_REMATCH[1]}"$'\n'
                    result+="rtt_worst_p50 ${BASH_REMATCH[2]}"$'\n'
                    result+="rtt_worst_p99 ${BASH_REMATCH[3]}"$'\n'
                    result+="rtt_worst_max ${BASH_REMATCH[4]}"$'\n'
                fi
                ;;
        esac
    done <<< "$text"

    echo "$result"
}
