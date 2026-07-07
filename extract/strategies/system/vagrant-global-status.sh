#!/bin/bash
## Name: vagrant-global-status
## Description: Extract machines from `vagrant global-status` output (skips header/rule/footer)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/vagrant-global-status/basic.txt

# `vagrant global-status` prints a header ("id name provider state directory"), a
# dashed rule line, one row per known machine, then a trailing explanatory
# paragraph. The header, rule, and footer are noise; each machine row (whose last
# field is its directory path) becomes a record.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: the vagrant header columns plus a dashed rule line.
    local line has_header=0 has_rule=0 rows=0
    while IFS= read -r line; do
        if [[ "$line" == *id*name*provider*state*directory* ]]; then
            has_header=1
            continue
        fi
        if [[ "$line" =~ ^-+[[:space:]]*$ ]]; then
            has_rule=1
            continue
        fi
        # A machine row: 5 whitespace fields whose last is an absolute path.
        if [[ "$line" =~ ^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/[^[:space:]]+[[:space:]]*$ ]]; then
            rows=$((rows + 1))
        fi
    done <<< "$text"
    if [[ $has_header -eq 1 && $has_rule -eq 1 && $rows -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line id name provider state directory
    while IFS= read -r line; do
        [[ "$line" =~ ^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/[^[:space:]]+[[:space:]]*$ ]] || continue
        read -r id name provider state directory _ <<< "$line"
        entry=$((entry + 1))
        result+="entry${entry}.id ${id}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.provider ${provider}"$'\n'
        result+="entry${entry}.state ${state}"$'\n'
        result+="entry${entry}.directory ${directory}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
