#!/bin/bash
## Name: git-branch-vv
## Description: Extract branches, heads and tracking info from `git branch -vv`
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/git-branch-vv/basic.txt

# `git branch -vv` prints one line per branch:
#   * main    a1b2c3d [origin/main] Fix null pointer in request handler
# a leading `* ` marks the current branch; the [..] tracking block is optional.

_gitbranchvv_is_line () {
    [[ "$1" =~ ^[*+[:space:]][[:space:]]*[^[:space:]]+[[:space:]]+[0-9a-f]+[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has_branch=0
    while IFS= read -r line; do
        _gitbranchvv_is_line "$line" && has_branch=1
    done <<< "$text"
    if [[ $has_branch -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line current name sha rest upstream message
    while IFS= read -r line; do
        _gitbranchvv_is_line "$line" || continue
        if [[ "$line" == "*"* ]]; then current=1; else current=0; fi
        # strip leading marker + whitespace
        line="${line#[*+ ]}"
        line="${line#"${line%%[![:space:]]*}"}"
        name="${line%%[[:space:]]*}"
        rest="${line#*[[:space:]]}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        sha="${rest%%[[:space:]]*}"
        rest="${rest#*[[:space:]]}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        if [[ "$rest" == "["* ]]; then
            upstream="${rest#[}"
            upstream="${upstream%%]*}"
            message="${rest#*] }"
        else
            upstream=""
            message="$rest"
        fi
        name="${name// /_}"; sha="${sha// /_}"
        upstream="${upstream// /_}"; message="${message// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.current ${current}"$'\n'
        result+="entry${entry}.branch ${name}"$'\n'
        result+="entry${entry}.sha ${sha}"$'\n'
        result+="entry${entry}.upstream ${upstream}"$'\n'
        result+="entry${entry}.message ${message}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
