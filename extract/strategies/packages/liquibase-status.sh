#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: liquibase-status
## Description: Extract pending changesets from `liquibase status` output (path::id::author)
## Version: 1.0
## Priority: 22
## Sample: samples/liquibase-status/basic.txt

# `liquibase status` prints an "N changesets have not been applied ..." header
# then one indented line per pending changeset of the form
# "<path>::<id>::<author>". The header is skipped; each "::"-delimited line
# becomes a record.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Require the liquibase status banner AND a `path::id::author` changeset line.
    # The banner keys this to liquibase — a bare `::.*::` match would otherwise grab
    # IPv6 socket rows (ss/netstat `:::80  :::*`).
    [[ "$text" == *"not been applied"* || "$text" == *"changeset"* || "$text" == *"changeSet"* ]] || return 1
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" != *"["* && "$line" =~ ^[[:space:]]*[^[:space:]:/]*/[^[:space:]]*::[^[:space:]:]+::[^[:space:]:]+ ]]; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *"::"*"::"* ]] || continue
        local body="$line"
        while [[ "$body" == " "* ]]; do body="${body# }"; done
        local path="${body%%::*}"
        local rest="${body#*::}"
        local id="${rest%%::*}"
        local author="${rest#*::}"
        entry=$((entry + 1))
        result+="entry${entry}.path ${path}"$'\n'
        result+="entry${entry}.id ${id}"$'\n'
        result+="entry${entry}.author ${author}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
