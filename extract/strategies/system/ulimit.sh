#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: ulimit
## Description: Extract resource limits from ulimit -a output
## Version: 1.0
## Priority: 20
## Sample: samples/ulimit/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # Distinctive: a description followed by a "(unit, -X)" or "(-X)" group and a value,
    # e.g. "core file size          (blocks, -c) 0" or "open files (-n) 1024".
    local re='\(([a-zA-Z0-9, ]*)-[a-zA-Z]\) +[^ ]+$'
    local hits=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ $re ]]; then
            hits=$((hits + 1))
        fi
    done
    if [[ $hits -ge 2 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local re='^(.*[^ ]) +\(([a-zA-Z0-9, ]*)-([a-zA-Z])\) +([^ ]+)$'
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        # Match: <description> (<unit>, -X) <value>   OR   <description> (-X) <value>
        if [[ "$line" =~ $re ]]; then
            local desc="${BASH_REMATCH[1]}"
            local unit="${BASH_REMATCH[2]}"
            local flag="${BASH_REMATCH[3]}"
            local value="${BASH_REMATCH[4]}"
            # Normalize description -> resource (spaces to underscores, trim)
            desc="${desc#"${desc%%[![:space:]]*}"}"
            desc="${desc%"${desc##*[![:space:]]}"}"
            local resource="${desc}"
            # The parenthesised unit (`blocks`, `kbytes`, `512 bytes`) is what
            # makes the value interpretable — `8192` without it doesn't say
            # whether it is bytes or kilobytes. Trim the `, ` that separated
            # it from the flag; a bare `(-X)` group has no unit and emits none.
            unit="${unit%"${unit##*[![:space:],]}"}"
            unit="${unit#"${unit%%[![:space:]]*}"}"
            entry=$((entry + 1))
            result+="entry${entry}.resource ${resource}"$'\n'
            [[ -n "$unit" ]] && result+="entry${entry}.unit ${unit}"$'\n'
            result+="entry${entry}.flag ${flag}"$'\n'
            result+="entry${entry}.value ${value}"$'\n'
        fi
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
