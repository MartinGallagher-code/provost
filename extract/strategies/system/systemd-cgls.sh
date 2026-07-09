#!/bin/bash
## Name: systemd-cgls
## Description: Extract control-group nodes from `systemd-cgls` tree output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/systemd-cgls/basic.txt

# `systemd-cgls` prints a control-group hierarchy: a "Control group /:" header
# followed by one node per line, indented with box-drawing connectors
# (│ ├─ └─ ─). Each node line becomes a record whose single field is the line
# with the tree glyphs and leading indentation stripped (spaces -> _).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: the "Control group" header plus cgroup slice/scope nodes.
    [[ "$text" == *"Control group"* ]] || return 1
    [[ "$text" == *".slice"* || "$text" == *".scope"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip the "Control group /:" header (root description line).
        [[ "$line" == "Control group"* ]] && continue
        s="$line"
        # Strip box-drawing glyphs: │ ├ └ ─
        s="${s//$'\xe2\x94\x82'/}"
        s="${s//$'\xe2\x94\x9c'/}"
        s="${s//$'\xe2\x94\x94'/}"
        s="${s//$'\xe2\x94\x80'/}"
        # Trim leading whitespace left behind by the connectors.
        while [[ "$s" == " "* || "$s" == $'\t'* ]]; do s="${s#[$' \t']}"; done
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.A ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
