#!/bin/bash
## Name: pkg-config
## Description: Extract packages from `pkg-config --list-all` output
## Version: 1.0
## Priority: 21
## Sample: samples/pkg-config/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1

    # Decline anything with an all-caps column header (`prlimit`'s
    # "RESOURCE DESCRIPTION SOFT HARD UNITS", ps/who/aws headers). `pkg-config
    # --list-all` never prints a header — its first line is a package — so a
    # multi-token ALL-CAPS first line means this is a real table for
    # aligned-columns, not a name/description list.
    local _first="" _fl
    while IFS= read -r _fl; do
        [[ -z "${_fl//[[:space:]]/}" ]] && continue
        _first="$_fl"; break
    done <<< "$text"
    if [[ "$_first" =~ ^[[:space:]]*[A-Z][A-Z0-9_]*([[:space:]]+[A-Z][A-Z0-9_()%-]*)+[[:space:]]*$ ]]; then
        return 1
    fi

    # Distinctive: every line is "<package-name>   <prose description>".
    # A package name starts with a letter and is a single token; the remainder
    # is a free-text description (contains an alphabetic word). Reject anything
    # that looks like a sized/percentage table (df) or an arrow map (ldconfig).
    local lines=0 line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # No size/percentage tables, no "=>" maps, no parenthesised version lists.
        [[ "$line" == *"%"* || "$line" == *"=>"* ]] && return 1
        local name="${line%%[[:space:]]*}"
        # Package name: starts with a letter, package-ish characters only.
        [[ "$name" =~ ^[A-Za-z][A-Za-z0-9._+-]*$ ]] || return 1
        local rest="${line#"$name"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        # Description must be present and contain a real word (2+ letters).
        [[ -n "$rest" && "$rest" =~ [A-Za-z][A-Za-z] ]] || return 1
        lines=$((lines + 1))
    done <<< "$text"
    if [[ $lines -ge 2 ]]; then
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
        local name="${line%%[[:space:]]*}"
        local desc="${line#"$name"}"
        desc="${desc#"${desc%%[![:space:]]*}"}"
        [[ -z "$name" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.description ${desc}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
