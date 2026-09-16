#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: path-line-content
## Description: `path:LINE:content` match lines (grep -n) -> file/line/content rows
## Version: 1.0
## Priority: 44
## Sample: samples/path-line-content/basic.txt

# `grep -n` (and friends) print one match per line as `path:LINE:content`:
#
#   src/main.py:12:def parse_config(path):
#   src/utils.py:7:# helper for parsing input
#
# The reviewer: "Key/value" — split it, don't leave one blob. The canonical
# tidy for a match list is three columns:
#
#   file          line   content
#   src/main.py   12     def parse_config(path):
#
# Auto-detect requires EVERY non-blank line to be `path:INT:content` where the
# path holds a `.` or `/` (it names a file) and the content does NOT itself
# start `INT:` — that second-integer shape is vimgrep's `path:LINE:COL:...`,
# which a richer parse already handles and must not be stolen.

_plc_re='^([^:[:space:]]+):([0-9]+):(.*)$'
_plc_col='^[0-9]+:'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_plc_re ]] || return 1
        [[ "${BASH_REMATCH[1]}" == *[./]* ]] || return 1
        [[ "${BASH_REMATCH[3]}" =~ $_plc_col ]] && return 1
        n=$((n + 1))
    done <<< "$text"
    [[ $n -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=75
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_plc_re ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.file ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.line ${BASH_REMATCH[2]}"$'\n'
        local c="${BASH_REMATCH[3]}"
        c="${c#"${c%%[![:space:]]*}"}"
        [[ -n "$c" ]] && result+="entry${entry}.content ${c}"$'\n'
    done <<< "$text"
    [[ $entry -ge 1 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}
