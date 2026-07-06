#!/bin/bash
## Name: ldconfig-p
## Description: Extract shared libraries from `ldconfig -p` cache listing
## Version: 1.0
## Priority: 22
## Sample: samples/ldconfig-p/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: the "NNN libs found in cache" summary line plus at least one
    # "soname (info) => /path" library entry.
    local first=1 has_summary=0 has_lib=0 line
    while IFS= read -r line; do
        if [[ $first -eq 1 ]]; then
            first=0
            [[ "$line" =~ ^[0-9]+[[:space:]]libs[[:space:]]found[[:space:]]in[[:space:]]cache ]] && has_summary=1
            continue
        fi
        local t="${line#"${line%%[![:space:]]*}"}"
        [[ "$t" == *"("*")"*"=> "* ]] && has_lib=1
    done <<< "$text"
    if [[ $has_summary -eq 1 && $has_lib -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local first=1 line
    while IFS= read -r line; do
        if [[ $first -eq 1 ]]; then
            first=0
            # Skip the "NNN libs found in cache ..." summary line.
            continue
        fi
        local t="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$t" ]] && continue
        [[ "$t" == *"("*")"*"=> "* ]] || continue
        local soname="${t%% (*}"
        local info="${t#*(}"; info="${info%%)*}"
        local path="${t##*=> }"
        entry=$((entry + 1))
        result+="entry${entry}.soname ${soname}"$'\n'
        result+="entry${entry}.info ${info}"$'\n'
        result+="entry${entry}.path ${path}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
