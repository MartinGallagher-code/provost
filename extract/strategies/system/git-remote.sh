#!/bin/bash
## Name: git-remote
## Description: Extract configured remotes from `git remote -v`
## Version: 1.0
## Priority: 13
## Sample: samples/git-remote/basic.txt

# `git remote -v` prints tab-separated rows:
#   origin<TAB>git@github.com:acme/widget.git (fetch)
#   origin<TAB>git@github.com:acme/widget.git (push)

_gitremote_is_line () {
    [[ "$1" =~ ^[^[:space:]]+$'\t'.+[[:space:]]\((fetch|push)\)[[:space:]]*$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line
    while IFS= read -r line; do
        if _gitremote_is_line "$line"; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        _gitremote_is_line "$line" || continue
        local remote="${line%%$'\t'*}"
        local rest="${line#*$'\t'}"
        # direction is the trailing (fetch|push)
        local direction="${rest##*\(}"
        direction="${direction%\)*}"
        local url="${rest% (*}"
        entry=$((entry + 1))
        result+="entry${entry}.remote ${remote}"$'\n'
        result+="entry${entry}.url ${url}"$'\n'
        result+="entry${entry}.direction ${direction}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
