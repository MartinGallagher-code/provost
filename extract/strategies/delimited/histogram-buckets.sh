#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: histogram-buckets
## Description: `@map:` sections of `[bucket) count |@@@ bar|` histogram rows (bpftrace) -> map/bucket/count rows — hint-routed
## Version: 1.0
## Priority: 47
## Sample: samples/histogram-buckets/basic.txt

# bpftrace prints histograms as `@name:` sections over bucket rows — a
# bracketed range (or single value), a count, and an @-bar:
#
#   @bytes:
#   [16, 32)              12 |@@@@                          |
#   [1]                  882 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
#
# The reviewer: parse it. The bar is a visualization of the count, not data,
# so it drops; the map name carries down and the bucket keeps its range
# notation:
#
#   map     bucket     count
#   bytes   [16, 32)   12
#   bytes   [1]        882
#
# Attaching/^C chrome and blank lines are skipped.
#
# HINT-ONLY: routes on the bucket-row shape via hints.tsv.

_hb_row='^(\[[^])]*[])])[[:space:]]+([0-9]+)[[:space:]]+\|'
_hb_map='^@([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*$'

strategy_extract () {
    local text="$1"
    local line result="" entry=0 map=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        if [[ "$s" =~ $_hb_map ]]; then
            map="${BASH_REMATCH[1]}"
            continue
        fi
        [[ "$s" =~ $_hb_row ]] || continue
        entry=$((entry + 1))
        [[ -n "$map" ]] && result+="entry${entry}.map ${map}"$'\n'
        result+="entry${entry}.bucket ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.count ${BASH_REMATCH[2]}"$'\n'
    done <<< "$text"
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
