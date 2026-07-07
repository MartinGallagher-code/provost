#!/bin/bash
## Name: bundle-outdated
## Description: Extract outdated gems from `bundle outdated` output (skips fetch preamble + header)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/bundle-outdated/basic.txt

# `bundle outdated` prints a "Fetching gem metadata..." / "Resolving
# dependencies..." preamble, then a column header
# ("Gem  Current  Latest  Requested  Groups"), then one row per outdated gem.
# The preamble and header are noise; only the gem rows are data. Each gem becomes
# a record with its name and its current/latest versions.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: bundler's fetch preamble plus the Current/Latest header.
    [[ "$text" == *"Fetching gem metadata"* ]] || return 1
    local line has_header=0 rows=0
    while IFS= read -r line; do
        if [[ "$line" == Gem*Current*Latest* ]]; then
            has_header=1
            continue
        fi
        # A gem row: name, then two version-looking tokens (start with a digit).
        if [[ "$line" =~ ^[A-Za-z0-9._-]+[[:space:]]+[0-9][^[:space:]]*[[:space:]]+[0-9][^[:space:]]* ]]; then
            rows=$((rows + 1))
        fi
    done <<< "$text"
    if [[ $has_header -eq 1 && $rows -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line name current latest
    while IFS= read -r line; do
        [[ "$line" == Gem*Current*Latest* ]] && continue
        [[ "$line" =~ ^[A-Za-z0-9._-]+[[:space:]]+[0-9][^[:space:]]*[[:space:]]+[0-9][^[:space:]]* ]] || continue
        # First three whitespace-separated tokens: name, current, latest.
        read -r name current latest _ <<< "$line"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.current ${current}"$'\n'
        result+="entry${entry}.latest ${latest}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
