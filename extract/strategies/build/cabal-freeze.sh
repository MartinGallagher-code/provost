#!/bin/bash
## Name: cabal-freeze
## Description: Extract package constraints from `cabal freeze` (cabal.project.freeze)
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/cabal-freeze/basic.txt

# `cabal freeze` emits a single `constraints:` block, one package per line as
# "<pkg> ==<version>," with a leading "constraints:" on the first line and the
# rest indented. Each non-blank line is one dependency; the cleaned value is the
# line with the "constraints:" prefix, surrounding whitespace and trailing comma
# stripped (single column, one record per dependency).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local first="" nb=0 line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        [[ $nb -eq 1 ]] && first="$line"
    done <<< "$text"
    [[ $nb -eq 0 ]] && return 1
    # First non-blank line begins the constraints block, and the block carries
    # `==` version pins. This is specific to cabal's freeze output.
    if [[ "$first" == constraints:* && "$text" == *" =="* ]]; then
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
        s="${s#constraints:}"
        # trim leading/trailing whitespace
        s="${s#"${s%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        s="${s%,}"
        s="${s%"${s##*[![:space:]]}"}"
        s="${s// /_}"
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
