#!/bin/bash
## Name: apache2ctl-modules
## Description: Extract loaded modules from `apache2ctl -M` output (one record per module)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/apache2ctl-modules/basic.txt

# `apache2ctl -M` prints a "Loaded Modules:" header then one indented line per
# module of the form " <name>_module (<static|shared>)". Single-column data: the
# header is skipped and each module line becomes one record.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"Loaded Modules:"* ]] || return 1
    # At least one " name (static|shared)" module line.
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+[A-Za-z0-9_]+[[:space:]]+\((static|shared)\)[[:space:]]*$ ]]; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]+[A-Za-z0-9_]+[[:space:]]+\((static|shared)\)[[:space:]]*$ ]] || continue
        # Trim leading/trailing whitespace.
        local mod="$line"
        while [[ "$mod" == " "* ]]; do mod="${mod# }"; done
        while [[ "$mod" == *" " ]]; do mod="${mod% }"; done
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${mod}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
