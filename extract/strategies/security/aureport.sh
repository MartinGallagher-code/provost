#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: aureport
## Description: Extract audit events from `aureport` summary output (skips title + column header)
## Version: 1.0
## Priority: 26
## Sample: samples/aureport/basic.txt

# `aureport` prints a title line ("Authentication Report"), a "====" rule, a
# column header ("# date time acct host term exe success event"), another rule,
# then numbered event rows ("N. date time acct host term exe success event"). The
# title, rules, and header are noise; each numbered row becomes a record whose
# fields are the eight audit columns.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: the aureport column header plus numbered event rows.
    [[ "$text" =~ (^|$'\n')#[[:space:]]+date[[:space:]]+time ]] || return 1
    local line rows=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9]+\.[[:space:]] ]]; then
            rows=$((rows + 1))
        fi
    done <<< "$text"
    if [[ $rows -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line rest
    local date time acct host term exe success event
    while IFS= read -r line; do
        [[ "$line" =~ ^[0-9]+\.[[:space:]] ]] || continue
        # Drop the leading "N." record number, keep the eight columns.
        rest="${line#*.}"
        read -r date time acct host term exe success event _ <<< "$rest"
        entry=$((entry + 1))
        result+="entry${entry}.date ${date}"$'\n'
        result+="entry${entry}.time ${time}"$'\n'
        result+="entry${entry}.acct ${acct}"$'\n'
        result+="entry${entry}.host ${host}"$'\n'
        result+="entry${entry}.term ${term}"$'\n'
        result+="entry${entry}.exe ${exe}"$'\n'
        result+="entry${entry}.success ${success}"$'\n'
        result+="entry${entry}.event ${event}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
