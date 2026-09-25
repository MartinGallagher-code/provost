#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: double-colon-fields
## Description: envoy admin `a::b::c::d` records -> one positional column per `::` field
## Version: 1.0
## Priority: 43
## Sample: samples/double-colon-fields/basic.txt

# envoy's /clusters admin endpoint separates fields with a literal `::`:
#
#   api_cluster::10.0.2.1:8080::health_flags::healthy
#   api_cluster::default_priority::max_connections::1024
#
# line-records saw one token per line and emitted opaque cells. The reviewer:
# "use :: as the delimiter." Each `::`-separated field is its own positional
# column:
#
#   A            B               C                D
#   api_cluster  10.0.2.1:8080   health_flags     healthy
#
# Detection: >=2 non-blank lines, EVERY line space-free with >=2 `::`
# separators. Single colons inside a field (the endpoint's port) survive —
# only the double-colon splits.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        [[ "$line" == *[$' \t']* ]] && return 1
        [[ "$line" == *"::"*"::"* ]] || return 1
        n=$((n + 1))
    done
    [[ $n -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        entry=$((entry + 1))
        local rest="$line" i=0 part col
        while :; do
            if [[ "$rest" == *"::"* ]]; then
                part="${rest%%::*}"; rest="${rest#*::}"
            else
                part="$rest"; rest=""
            fi
            i=$((i + 1))
            col=$(printf "\\$(printf '%03o' $((64 + i)))")
            [[ -n "$part" ]] && result+="entry${entry}.${col} ${part}"$'\n'
            [[ -z "$rest" ]] && break
        done
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
