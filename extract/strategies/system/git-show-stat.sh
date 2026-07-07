#!/bin/bash
## Name: git-show-stat
## Description: Extract per-file diffstat lines from `git show --stat`
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/git-show-stat/basic.txt

# `git show --stat` prints one commit block; each changed file gets a line:
#   src/login.py         | 24 +++++++++++++++++++----
# The trailing `N files changed, ...` summary carries no `|` and is skipped.
# One record per file-stat line.

_gitshowstat_is_file () {
    [[ "$1" =~ \|[[:space:]]+[0-9]+[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has_commit=0 has_stat=0
    while IFS= read -r line; do
        [[ "$line" =~ ^commit[[:space:]][0-9a-f]{7,} ]] && has_commit=1
        _gitshowstat_is_file "$line" && has_stat=1
    done <<< "$text"
    if [[ $has_commit -eq 1 && $has_stat -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line path changes
    while IFS= read -r line; do
        _gitshowstat_is_file "$line" || continue
        path="${line%%|*}"
        changes="${line#*|}"
        path="${path#"${path%%[![:space:]]*}"}"
        path="${path%"${path##*[![:space:]]}"}"
        changes="${changes#"${changes%%[![:space:]]*}"}"
        changes="${changes%"${changes##*[![:space:]]}"}"
        path="${path// /_}"; path="${path//$'\t'/_}"
        changes="${changes// /_}"; changes="${changes//$'\t'/_}"
        entry=$((entry + 1))
        result+="entry${entry}.path ${path}"$'\n'
        result+="entry${entry}.changes ${changes}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
