#!/bin/bash
## Name: git-config-list-show-origin
## Description: Extract settings from `git config --list --show-origin` (origin<TAB>key=value)
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/git-config-list-show-origin/basic.txt

# `git config --list --show-origin` prints one setting per line as
# "<origin><TAB><key>=<value>" (origin is typically "file:<path>"). Each line
# becomes one record with the origin, key, and value.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line
    while IFS= read -r line; do
        if [[ "$line" == "file:"*$'\t'*"="* ]]; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line origin kv key value
    while IFS= read -r line; do
        [[ "$line" == *$'\t'*"="* ]] || continue
        IFS=$'\t' read -r origin kv <<< "$line"
        [[ -n "$kv" ]] || continue
        key="${kv%%=*}"
        value="${kv#*=}"
        key="${key// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.origin ${origin}"$'\n'
        result+="entry${entry}.key ${key}"$'\n'
        result+="entry${entry}.value ${value}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
