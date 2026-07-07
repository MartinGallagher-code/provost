#!/bin/bash
## Name: git-config-list-show-origin
## Description: Extract settings + origin files from `git config --list --show-origin`
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/git-config-list-show-origin/basic.txt

# Each line is `<origin><TAB><key>=<value>`, e.g.
#   file:/home/user/.gitconfig<TAB>user.name=Jane Developer

_gitcfgorigin_is_line () {
    [[ "$1" == *$'\t'*=* && "$1" == file:* ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has=0
    while IFS= read -r line; do
        _gitcfgorigin_is_line "$line" && has=1
    done <<< "$text"
    if [[ $has -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line origin kv key value
    while IFS= read -r line; do
        _gitcfgorigin_is_line "$line" || continue
        origin="${line%%$'\t'*}"
        kv="${line#*$'\t'}"
        key="${kv%%=*}"
        value="${kv#*=}"
        origin="${origin// /_}"; origin="${origin//$'\t'/_}"
        key="${key// /_}"
        value="${value// /_}"; value="${value//$'\t'/_}"
        entry=$((entry + 1))
        result+="entry${entry}.origin ${origin}"$'\n'
        result+="entry${entry}.key ${key}"$'\n'
        result+="entry${entry}.value ${value}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
