#!/bin/bash
## Name: dpkg-get-selections
## Description: Extract package selection states from `dpkg --get-selections`
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/dpkg-get-selections/basic.txt

# `dpkg --get-selections` prints "<package>\t<state>" per line, where state is
# one of install/deinstall/hold/purge/unknown. Each line is one record with
# package/status fields.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local nb=0 good=0 line last
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        last="${line##*[[:space:]]}"
        case "$last" in
            install|deinstall|hold|purge|unknown) good=$((good + 1)) ;;
        esac
    done <<< "$text"
    # Every non-blank line must end in a valid selection state.
    if [[ $nb -gt 0 && $good -eq $nb ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line pkg status
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        pkg="${line%%[[:space:]]*}"
        status="${line##*[[:space:]]}"
        [[ -z "$pkg" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.package ${pkg}"$'\n'
        result+="entry${entry}.status ${status}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
