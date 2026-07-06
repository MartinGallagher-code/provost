#!/bin/bash
## Name: composer-show
## Description: Extract packages from `composer show` output
## Version: 1.0
## Priority: 22
## Sample: samples/composer-show/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: every line is "<vendor/pkg> <version> <description>" where the
    # package name contains a slash and the second field is a dotted version.
    local lines=0 line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 2 ]] || return 1
        [[ "${f[0]}" == */* ]] || return 1
        [[ "${f[1]}" =~ ^v?[0-9]+\.[0-9]+ ]] || return 1
        lines=$((lines + 1))
    done <<< "$text"
    if [[ $lines -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 2 ]] || continue
        local pkg="${f[0]}" ver="${f[1]}"
        # Description is everything after the version token.
        local desc="${line#*"$ver"}"
        desc="${desc#"${desc%%[![:space:]]*}"}"
        entry=$((entry + 1))
        result+="entry${entry}.package ${pkg}"$'\n'
        result+="entry${entry}.version ${ver}"$'\n'
        [[ -n "$desc" ]] && result+="entry${entry}.description ${desc}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
