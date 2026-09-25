#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: fossil-status
## Description: Extract status lines from fossil status output
## Version: 1.0
## Priority: 26
## Sample: samples/fossil-status/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # fossil status: "repository:" / "checkout:" kv headers plus file-change
    # lines with verbs like EDITED / ADDED / DELETED.
    local has_repo=0 has_checkout=0 has_change=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        case "$line" in
            "repository:"*) has_repo=1 ;;
            "checkout:"*)   has_checkout=1 ;;
            EDITED\ *|ADDED\ *|DELETED\ *|MISSING\ *|RENAMED\ *|UPDATED\ *|CONFLICT\ *|EXTRA\ *)
                has_change=1 ;;
        esac
    done
    if [[ $has_repo -eq 1 && $has_checkout -eq 1 && $has_change -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local line cleaned
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Emit one record per non-blank status line (skip blanks only).
        [[ -z "$line" ]] && continue
        case "$line" in
            *[![:space:]]*) : ;;   # has non-whitespace
            *) continue ;;
        esac

        # Clean: trim ends, collapse internal whitespace runs, spaces -> underscore.
        cleaned="$line"
        cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"   # ltrim
        cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"   # rtrim
        # Collapse runs of whitespace to a single space.
        while [[ "$cleaned" == *"  "* ]]; do
            cleaned="${cleaned//  / }"
        done
        cleaned="${cleaned//$'\t'/ }"

        entry=$((entry + 1))
        result+="entry${entry}.line ${cleaned}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
