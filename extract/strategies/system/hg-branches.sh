#!/bin/bash
## Name: hg-branches
## Description: Extract named branches from `hg branches`
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/hg-branches/basic.txt

# `hg branches` prints one line per branch:
#   default          18:2f8a1c9b4d5e
#   stable           15:0f9e8d7c6b5a (inactive)
# name, then <rev>:<hash>, with an optional (inactive)/(closed) status.

_hgbranches_is_line () {
    [[ "$1" =~ ^[^[:space:]]+[[:space:]]+[0-9]+:[0-9a-f]+ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has=0
    while IFS= read -r line; do
        _hgbranches_is_line "$line" && has=1
    done <<< "$text"
    if [[ $has -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line name rest revhash rev hash status
    while IFS= read -r line; do
        _hgbranches_is_line "$line" || continue
        name="${line%%[[:space:]]*}"
        rest="${line#*[[:space:]]}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        revhash="${rest%%[[:space:]]*}"
        rev="${revhash%%:*}"
        hash="${revhash#*:}"
        if [[ "$rest" == *"("* ]]; then
            status="${rest#*(}"
            status="${status%%)*}"
        else
            status="active"
        fi
        name="${name// /_}"; hash="${hash// /_}"; status="${status// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.branch ${name}"$'\n'
        result+="entry${entry}.rev ${rev}"$'\n'
        result+="entry${entry}.hash ${hash}"$'\n'
        result+="entry${entry}.status ${status}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
