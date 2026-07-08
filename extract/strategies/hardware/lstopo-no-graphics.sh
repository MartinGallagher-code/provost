#!/bin/bash
## Name: lstopo-no-graphics
## Description: Extract topology nodes from `lstopo --no-graphics` (hwloc) output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/lstopo-no-graphics/basic.txt

# `lstopo --no-graphics` prints the hwloc machine topology as an indented tree:
# Machine, Package, NUMANode, caches/cores/PUs (joined with " + "), HostBridge,
# PCI bridges and devices, disks and Misc modules. Each non-blank node line
# becomes a record whose single field is the line with leading indentation
# stripped (spaces -> _).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # NOTE: sample starts with "Machine (" (not "["), so _is_json is safe here.
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == "Machine ("* || "$text" == *$'\n'"Machine ("* ]] || return 1
    # Distinctive to the graphical topology dump (absent from bare hwloc lstopo).
    [[ "$text" == *"HostBridge"* || "$text" == *"Block(Disk)"* || "$text" == *" + Core "* ]] || return 1
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
