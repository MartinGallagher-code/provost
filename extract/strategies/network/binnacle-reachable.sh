#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: binnacle-reachable
## Description: Extract host reachability rows from `reachable` (binnacle) server-list output
## Version: 1.0
## Priority: 22
## Sample: samples/binnacle-reachable/basic.txt

# `reachable` (binnacle's tool) rewrites a server-list file in place: a
# reachable host stays as a bare (optionally trailing-commented) line; an
# unreachable one is commented out and tagged with
# `#[unreachable] <reason> - <date>`, e.g.:
#   # production web tier
#   web01
#   # db07  #[unreachable] pings but ssh does not answer - 2026-08-15
#   cache02  # the slow one
# Plain `#`-prefixed lines with no `#[unreachable]` tag are ordinary human
# comments/section headers, not unreachable markers, and are skipped.

_brch_re_unreachable='^[[:space:]]*#[[:space:]]*([^[:space:]]+)[[:space:]]+#\[unreachable\][[:space:]]*(.*)$'
_brch_re_reason_date='^(.*)[[:space:]]-[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]*$'
_brch_re_comment='^[[:space:]]*#'
_brch_re_host='^[[:space:]]*([^[:space:]#]+)([[:space:]]+#[[:space:]]*(.*))?[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    [[ "$text" == *'#[unreachable]'* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" n=0 line

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Skip blank lines.
        [[ "${line}" != *[![:space:]]* ]] && continue

        if [[ "$line" == *'#[unreachable]'* ]]; then
            [[ "$line" =~ $_brch_re_unreachable ]] || continue
            local host="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"
            local reason="" checked_date=""
            if [[ "$rest" =~ $_brch_re_reason_date ]]; then
                reason="${BASH_REMATCH[1]}"
                checked_date="${BASH_REMATCH[2]}"
            fi

            n=$((n + 1))
            local p="entry${n}."
            result+="${p}host ${host}"$'\n'
            result+="${p}reachable 0"$'\n'
            [[ -n "$reason" ]] && result+="${p}reason ${reason}"$'\n'
            [[ -n "$checked_date" ]] && result+="${p}checked_date ${checked_date}"$'\n'
            continue
        fi

        # A line whose first non-blank char is "#" and that carries no
        # #[unreachable] tag is a plain comment / section header — skip it.
        [[ "$line" =~ $_brch_re_comment ]] && continue

        # Reachable host line, optionally with a trailing inline note.
        [[ "$line" =~ $_brch_re_host ]] || continue
        local host="${BASH_REMATCH[1]}"
        local note="${BASH_REMATCH[3]}"
        _trim "$note"
        note="$_TRIMMED"

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}host ${host}"$'\n'
        result+="${p}reachable 1"$'\n'
        [[ -n "$note" ]] && result+="${p}note ${note}"$'\n'
    done

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
