#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: git-annex-list
## Description: Extract per-file location tracking from `git annex list`
## Version: 1.0
## Priority: 22
## Sample: samples/git-annex-list/basic.txt

# `git annex list` prints a legend of remotes (here / |web / ||remote) then one
# line per file: a column of X/_ flags followed by the file path, e.g.
#   X__ video/clip1.mov

_gitannex_is_file () {
    # two-or-more X/_ flag chars, whitespace, then a path.
    [[ "$1" =~ ^[X_][X_]+[[:space:]]+[^[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has_file=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _gitannex_is_file "$line" && has_file=1
    done
    if [[ $has_file -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=92
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line status path
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _gitannex_is_file "$line" || continue
        status="${line%%[[:space:]]*}"
        path="${line#*[[:space:]]}"
        # ltrim any remaining leading whitespace on the path
        path="${path#"${path%%[![:space:]]*}"}"
        path="${path//$'\t'/_}"
        entry=$((entry + 1))
        result+="entry${entry}.flags ${status}"$'\n'
        result+="entry${entry}.path ${path}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
