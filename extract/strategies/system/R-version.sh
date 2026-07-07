#!/bin/bash
## Name: R-version
## Description: Extract version fields from `R --version` banner
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/R-version/basic.txt

# `R --version` opens with 'R version 4.3.2 (2023-10-31) -- "Eye Holes"' and a
# "Platform: <triple> (...)" line, followed by license text. One wide key/value
# record: product, version, date, nickname, platform.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local first="" line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        first="$line"; break
    done <<< "$text"
    if [[ "$first" == "R version "* && "$text" == *"Platform:"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" ver="" date="" nick="" plat=""
    if [[ "$text" =~ R[[:space:]]version[[:space:]]([0-9][0-9A-Za-z.+-]*) ]]; then
        ver="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ \(([0-9]{4}-[0-9]{2}-[0-9]{2})\) ]]; then
        date="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ \"([^\"]+)\" ]]; then
        nick="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ Platform:[[:space:]]*([^[:space:]]+) ]]; then
        plat="${BASH_REMATCH[1]}"
    fi
    result+="entry1.product R"$'\n'
    result+="entry1.version ${ver// /_}"$'\n'
    result+="entry1.date ${date// /_}"$'\n'
    result+="entry1.nickname ${nick// /_}"$'\n'
    result+="entry1.platform ${plat// /_}"$'\n'
    result+="total_entries 1"$'\n'
    echo "$result"
}
