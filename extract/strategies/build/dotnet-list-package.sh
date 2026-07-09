#!/bin/bash
## Name: dotnet-list-package
## Description: Extract package references from `dotnet list package` output
## Version: 1.0
## Priority: 20
## Sample: samples/dotnet-list-package/basic.txt

# `dotnet list package` prints a "Top-level Package / Requested / Resolved"
# table where each package row is marked with "> ". Each ">" row is one record
# with package/requested/resolved fields.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    if [[ "$text" == *"Top-level Package"* && "$text" == *"Resolved"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s pkg req res rest
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Trim leading whitespace, then require the "> " row marker.
        s="${line#"${line%%[![:space:]]*}"}"
        [[ "$s" == "> "* ]] || continue
        s="${s#> }"
        s="${s#"${s%%[![:space:]]*}"}"
        pkg="${s%%[[:space:]]*}"; rest="${s#"$pkg"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        req="${rest%%[[:space:]]*}"; rest="${rest#"$req"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        res="${rest%%[[:space:]]*}"
        [[ -z "$pkg" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.package ${pkg}"$'\n'
        result+="entry${entry}.requested ${req}"$'\n'
        result+="entry${entry}.resolved ${res}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
