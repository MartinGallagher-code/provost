#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: psql-expanded
## Description: psql \x expanded output — one record per -[ RECORD N ] block of key | value lines
## Version: 1.0
## Priority: 9
## Sample: samples/psql-expanded/basic.txt

# psql's expanded display (\x on, any query):
#   -[ RECORD 1 ]---------+------------------------------
#   datname               | orders
#   state                 | active
#   -[ RECORD 2 ]---------+------------------------------
#   datname               | metrics
#   ...
# One entry per RECORD block; each `key | value` line becomes entryN.key.
# This is a FORMAT parser: it keys on the `-[ RECORD N ]` separator psql
# always prints in expanded mode, never on any table's column names.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"-[ RECORD 1 ]"* ]] || return 1
    # Require at least one `key | value` body line so a stray marker in a log
    # can't trigger a whole-file parse.
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\| ]]; then
            _STRATEGY_CONFIDENCE=80
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1" result="" line key val entry=0 fields=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # `-[ RECORD N ]---+---` opens the next record.
        if [[ "$line" == *"-[ RECORD"* ]]; then
            entry=$((entry + 1))
            continue
        fi
        [[ $entry -eq 0 ]] && continue
        [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\|[[:space:]]?(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        val="${val%"${val##*[![:space:]]}"}"   # rtrim
        val="${val//$'\t'/_}"
        result+="entry${entry}.${key} ${val}"$'\n'
        fields=$((fields + 1))
    done
    [[ $fields -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
