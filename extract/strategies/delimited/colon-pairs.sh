#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: colon-pairs
## Description: Inline "Label: value  Label: value" status lines (mysqladmin status, memcached/redis one-liners)
## Version: 1.0
## Priority: 11
## Sample: samples/colon-pairs/basic.txt

# The one-line status format: several "Label: value" pairs run together on a
# single line, labels possibly multi-word:
#
#   Uptime: 58234  Threads: 3  Slow queries: 2  Queries per second avg: 2.223
#
# One record per line. Split on ": " boundaries; a value is the first
# whitespace token after the colon, and any remaining words before the next
# colon belong to the NEXT label ("2  Opens" -> value 2, next label Opens).

# _cp_pairs_on_line_v LINE — the same count in _CP_NPAIRS, without the
# command-substitution fork per line.
_cp_pairs_on_line_v () {
    local l="$1" n=0
    while [[ "$l" == *": "* ]]; do
        n=$((n + 1))
        l="${l#*: }"
    done
    _CP_NPAIRS=$n
}

_cp_pairs_on_line () {
    # Count ": " pairs that look like "word: token"
    local l="$1" n=0
    while [[ "$l" == *": "* ]]; do
        n=$((n + 1))
        l="${l#*: }"
    done
    printf '%s' "$n"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line lines=0 good=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        lines=$((lines + 1))
        [[ $lines -gt 4 ]] && return 1        # a STATUS one-liner block, not a document
        # Need >=4 inline pairs on the line, and the line must not START with
        # indentation (yaml/colons documents) nor contain " = " (kv blocks).
        [[ "$line" == [[:space:]]* || "$line" == *" = "* ]] && return 1
        _cp_pairs_on_line_v "$line"
        [[ "$_CP_NPAIRS" -ge 4 ]] && good=$((good + 1))
    done
    if [[ $good -ge 1 && $good -eq $lines ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1" result="" line entry=0 fields=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        [[ "$line" != *": "* ]] && continue
        entry=$((entry + 1))
        # Walk "label: value rest..." — value is the first token after the
        # colon; leftover words accumulate into the next label.
        local rest="$line" label value seg
        label="${rest%%: *}"
        rest="${rest#*: }"
        while :; do
            if [[ "$rest" == *": "* ]]; then
                seg="${rest%%: *}"           # "<value> <next label words>"
                rest="${rest#*: }"
                value="${seg%%[[:space:]]*}"
                local next="${seg#"$value"}"
                next="${next#"${next%%[![:space:]]*}"}"
                result+="entry${entry}.${label// /_} ${value}"$'\n'
                fields=$((fields + 1))
                label="$next"
            else
                result+="entry${entry}.${label// /_} ${rest}"$'\n'
                fields=$((fields + 1))
                break
            fi
        done
    done
    [[ $fields -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
