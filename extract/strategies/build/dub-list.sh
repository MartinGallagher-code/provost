#!/bin/bash
## Name: dub-list
## Description: Extract packages from `dub list` (D package manager) output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/dub-list/basic.txt

# `dub list` prints a header line ("Packages present in the system and known to
# dub:") then one indented package per line as "<name> <version>: <path>". Each
# package line is one record; the cleaned value is the trimmed line (single
# column).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    if [[ "$text" == *"known to dub:"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s nb=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        # Skip the header line ("... known to dub:").
        [[ "$line" == *"known to dub:"* ]] && continue
        s="$line"
        s="${s#"${s%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
