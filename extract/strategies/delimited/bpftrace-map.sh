#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: bpftrace-map
## Description: bpftrace `@map[key1, key2]: count` histogram output -> map/key1/key2/value columns
## Version: 1.0
## Priority: 43
## Sample: samples/bpftrace-map/basic.txt

# bpftrace prints its aggregation maps as `@name[keys]: value`, with the
# attach/`^C` chrome around them:
#
#   Attaching 1 probe...
#   ^C
#
#   @syscalls[read]: 44210
#   @count[chrome, 3391]: 5521
#
# The reviewer's columns: A = the map name (`@` dropped), B = the first
# bracket item, C = the second bracket item (blank when there is only one),
# D = the value after the colon. Chrome lines (`Attaching …`, `^C`, blanks)
# are dropped.
#
#   map       key1    key2  value
#   syscalls  read          44210
#   count     chrome  3391  5521
#
# Detection: >=2 `@name[…]: value` lines, and every non-blank line is either
# one of those or recognisable chrome.

_bm_re='^@([A-Za-z_][A-Za-z0-9_]*)\[([^]]*)\]:[[:space:]]*(.+)$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line maps=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_bm_re ]]; then maps=$((maps + 1)); continue; fi
        # Tolerated chrome: the attach banner or a bare `^C` interrupt.
        [[ "$line" == "Attaching "* || "$line" == *"probe"*"..." || "$line" == "^C" ]] && continue
        return 1
    done <<< "$text"
    [[ $maps -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ $_bm_re ]] || continue
        local name="${BASH_REMATCH[1]}" keys="${BASH_REMATCH[2]}" val="${BASH_REMATCH[3]}"
        val="${val%"${val##*[![:space:]]}"}"
        # Bracket items split on `, `.
        local k1="$keys" k2=""
        if [[ "$keys" == *", "* ]]; then
            k1="${keys%%, *}"; k2="${keys#*, }"
        fi
        entry=$((entry + 1))
        result+="entry${entry}.map ${name}"$'\n'
        result+="entry${entry}.key1 ${k1}"$'\n'
        [[ -n "$k2" ]] && result+="entry${entry}.key2 ${k2}"$'\n'
        result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
