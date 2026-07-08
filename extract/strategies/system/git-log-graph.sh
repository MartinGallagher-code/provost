#!/bin/bash
## Name: git-log-graph
## Description: Extract commits from `git log --graph --oneline`
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/git-log-graph/basic.txt

# `git log --graph --oneline` draws an ASCII graph; commit lines carry a `*`
# node followed by an abbreviated sha and subject:
#   * a1b2c3d Add login form validation
#   | * d4e5f6a Add search indexing
# Pure-glyph lines (|\ , |/ , | ) carry no commit and are skipped.

_gitloggraph_is_commit () {
    [[ "$1" =~ ^[|/\\\*[:space:]]*\*[[:space:]]+[0-9a-f]+[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has=0
    while IFS= read -r line; do
        _gitloggraph_is_commit "$line" && has=1
    done <<< "$text"
    if [[ $has -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line rest sha message
    while IFS= read -r line; do
        _gitloggraph_is_commit "$line" || continue
        # drop everything up to and including the `*` node marker
        rest="${line#*\*}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        sha="${rest%%[[:space:]]*}"
        message="${rest#*[[:space:]]}"
        message="${message#"${message%%[![:space:]]*}"}"
        message="${message//$'\t'/_}"
        entry=$((entry + 1))
        result+="entry${entry}.commit ${sha}"$'\n'
        result+="entry${entry}.message ${message}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
