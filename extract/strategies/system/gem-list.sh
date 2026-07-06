#!/bin/bash
## Name: gem-list
## Description: Extract installed gems from `gem list` output
## Version: 1.0
## Priority: 22
## Sample: samples/gem-list/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: every line is "<name> (<version>[, <version>...])" where the
    # parenthesised list starts with a digit (a version).
    local lines=0 line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[A-Za-z0-9._-]+[[:space:]]\([0-9][0-9A-Za-z.,[:space:]-]*\)$ ]] || return 1
        lines=$((lines + 1))
    done <<< "$text"
    if [[ $lines -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == *"("*")"* ]] || continue
        local name="${line%% (*}"
        local versions="${line#*(}"; versions="${versions%)*}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.versions ${versions}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
