#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: git-bisect-log
## Description: Extract bisect actions from `git bisect log`
## Version: 1.0
## Priority: 22
## Sample: samples/git-bisect-log/basic.txt

# `git bisect log` interleaves `# good:/# bad:` comments with the replayable
# `git bisect <verb> [rev]` command lines. We emit one record per command line.

_gitbisect_is_cmd () {
    [[ "$1" =~ ^git[[:space:]]bisect[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has_cmd=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _gitbisect_is_cmd "$line" && has_cmd=1
    done
    if [[ $has_cmd -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line rest action ref
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _gitbisect_is_cmd "$line" || continue
        rest="${line#git bisect }"
        action="${rest%%[[:space:]]*}"
        if [[ "$rest" == *" "* ]]; then
            ref="${rest#* }"
            ref="${ref#"${ref%%[![:space:]]*}"}"
        else
            ref=""
        fi
        entry=$((entry + 1))
        result+="entry${entry}.action ${action}"$'\n'
        result+="entry${entry}.ref ${ref}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
