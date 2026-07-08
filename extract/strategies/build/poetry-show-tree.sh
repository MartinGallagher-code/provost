#!/bin/bash
## Name: poetry-show-tree
## Description: Extract dependency lines from `poetry show --tree` output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/poetry-show-tree/basic.txt

# `poetry show --tree` prints a root package ("<name> <ver> <description>") then
# a Unicode tree of "<name> <constraint>" nodes. Every non-blank line is one
# record; the cleaned value strips the leading tree glyphs (single column).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Box tree glyphs, but NOT a pnpm "dependencies:" header (pnpm-why) and NOT
    # npm ls, whose entries are `name@version` (poetry uses `name version`).
    if [[ ( "$text" == *"├──"* || "$text" == *"└──"* ) \
          && "$text" != *"dependencies:"* && "$text" != *"@"* \
          && "$text" != *"Image Layers"* && "$text" != *"Image ID:"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        s="$line"
        while [[ -n "$s" && "$s" != [A-Za-z0-9]* ]]; do s="${s#?}"; done
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
