#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: git-log-stat
## Description: Extract per-file diffstat lines from `git log --stat`
## Version: 1.0
## Priority: 13
## Sample: samples/git-log-stat/basic.txt

# `git log --stat` prints commit blocks; each changed file gets a line:
#   src/login.py         | 24 +++++++++++++++++++----
# The trailing `N files changed, ...` summary carries no `|` and is skipped.
# One record per file-stat line, across all commit blocks.

_gitlogstat_is_file () {
    [[ "$1" =~ \|[[:space:]]+[0-9]+[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has_commit=0 has_stat=0
    while IFS= read -r line; do
        [[ "$line" =~ ^commit[[:space:]][0-9a-f]{7,} ]] && has_commit=1
        _gitlogstat_is_file "$line" && has_stat=1
    done <<< "$text"
    if [[ $has_commit -eq 1 && $has_stat -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line path changes
    while IFS= read -r line; do
        _gitlogstat_is_file "$line" || continue
        path="${line%%|*}"
        changes="${line#*|}"
        path="${path#"${path%%[![:space:]]*}"}"
        path="${path%"${path##*[![:space:]]}"}"
        changes="${changes#"${changes%%[![:space:]]*}"}"
        changes="${changes%"${changes##*[![:space:]]}"}"
        path="${path//$'\t'/_}"
        changes="${changes//$'\t'/_}"
        entry=$((entry + 1))
        result+="entry${entry}.path ${path}"$'\n'
        result+="entry${entry}.changes ${changes}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
