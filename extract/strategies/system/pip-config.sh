#!/bin/bash
## Name: pip-config
## Description: Extract settings from `pip config list` output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/pip-config/basic.txt

# `pip config list` prints one setting per line as "<section>.<key>='<value>'".
# One wide key/value record: each setting becomes a field (dotted section.key
# name) whose value has the surrounding single quotes stripped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local nb=0 good=0 line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        # section.key='value'
        [[ "$line" =~ ^[A-Za-z][A-Za-z0-9_-]*\.[A-Za-z0-9_-]+=\'.*\'$ ]] && good=$((good + 1))
    done <<< "$text"
    if [[ $nb -gt 0 && $good -eq $nb ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line key val
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" != *=* ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        # Strip surrounding single quotes.
        val="${val#\'}"
        val="${val%\'}"
        # Sanitise the field-name suffix (spaces -> _), keep the dotted form.
        key="${key// /_}"
        [[ -z "$key" ]] && continue
        entry=$((entry + 1))
        result+="entry1.${key} ${val// /_}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
