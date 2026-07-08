#!/bin/bash
## Name: lshw-network
## Description: Extract per-line detail from `lshw -c network` output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/lshw-network/basic.txt

# `lshw -c network` prints one or more "*-network" device blocks, each a set of
# indented "key: value" detail lines. This class-filtered dump has no other
# component classes. Each non-blank line becomes a record whose single field is
# the line with leading indentation stripped (spaces -> _).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: a network device block, and NOT a full multi-class lshw dump.
    [[ "$text" == *"*-network"* ]] || return 1
    [[ "$text" == *"logical name:"* ]] || return 1
    [[ "$text" == *"*-cpu"* || "$text" == *"*-memory"* ]] && return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        s="$line"
        # Trim leading whitespace.
        while [[ "$s" == " "* || "$s" == $'\t'* ]]; do s="${s#[$' \t']}"; done
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
