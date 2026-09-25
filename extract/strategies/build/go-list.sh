#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: go-list
## Description: Extract module paths from `go list -m all` output (main module + dependencies)
## Version: 1.0
## Priority: 26
## Sample: samples/go-list/basic.txt

# `go list -m all` prints the main module on the first line (path only, no
# version), then one dependency per line as "<path> <version>" (version like
# v1.9.1). Every non-blank line is one module; the single-column value is the
# module path (first token), which is unique per row.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local first="" nb=0 versioned=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        nb=$((nb + 1))
        if [[ $nb -eq 1 ]]; then
            first="$line"
            # Main module: a single bare path token containing both '.' and '/'.
            [[ "$first" =~ ^[^[:space:]]+$ && "$first" == *.*/* ]] || return 1
            continue
        fi
        # Dependency lines: "<path> <version>" with a v-prefixed semantic version.
        if [[ "$line" =~ ^[^[:space:]]+\ v[0-9][0-9A-Za-z.+-]*$ ]]; then
            versioned=$((versioned + 1))
        else
            return 1
        fi
    done
    if [[ $versioned -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        local path="${line%%[[:space:]]*}"
        entry=$((entry + 1))
        result+="entry${entry}.A ${path}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
