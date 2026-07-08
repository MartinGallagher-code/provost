#!/bin/bash
## Name: getconf
## Description: Extract NAME/value pairs from `getconf -a` output (every line is a record)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/getconf/basic.txt

# `getconf -a` prints one "NAME<spaces>value" pair per line. Names are uppercase
# identifiers (optionally leading underscore, e.g. _NPROCESSORS_ONLN); the value
# may be a number (possibly large or negative) or empty (limit unset). There is
# no header line — the first line is a real record, so every non-blank line is
# emitted as a name/value record.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local nb=0 line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local name="${line%%[[:space:]]*}"
        # Every non-blank line must start with an uppercase getconf-style name.
        [[ "$name" =~ ^_?[A-Z][A-Z0-9_]*$ ]] || return 1
        # A getconf line is "NAME value" (or bare "NAME") — at most 2 tokens. This
        # rejects 3-token records like memcached's "STAT <key> <value>".
        local _tk; _tk=(); read -ra _tk <<< "$line"
        [[ ${#_tk[@]} -le 2 ]] || return 1
        nb=$((nb + 1))
    done <<< "$text"
    if [[ $nb -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local name="${line%%[[:space:]]*}"
        # Value = remainder after the name, trimmed (may be empty).
        local value="${line#"$name"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.value ${value}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
