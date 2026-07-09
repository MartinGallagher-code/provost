#!/bin/bash
## Name: fwupdmgr-get-devices
## Description: Extract device tree lines from `fwupdmgr get-devices` output
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/fwupdmgr-get-devices/basic.txt

# `fwupdmgr get-devices` prints a device tree: a root ("Computer"), one branch
# per device (├─name: / └─name:) with indented "key: value" detail lines, and
# bare "│" spacer lines between devices. Each non-blank line becomes a record
# whose single field is the line with box-drawing glyphs and leading
# indentation stripped (spaces -> _); spacer lines clean to an empty field.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: fwupd device detail keys inside a box-drawing tree.
    [[ "$text" == *"Device ID:"* ]] || return 1
    [[ "$text" == *"Current version:"* ]] || return 1
    [[ "$text" == *$'\xe2\x94\x9c'* || "$text" == *$'\xe2\x94\x94'* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        s="$line"
        # Strip box-drawing glyphs: │ ├ └ ─
        s="${s//$'\xe2\x94\x82'/}"
        s="${s//$'\xe2\x94\x9c'/}"
        s="${s//$'\xe2\x94\x94'/}"
        s="${s//$'\xe2\x94\x80'/}"
        # Trim leading whitespace.
        while [[ "$s" == " "* || "$s" == $'\t'* ]]; do s="${s#[$' \t']}"; done
        entry=$((entry + 1))
        result+="entry${entry}.A ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
