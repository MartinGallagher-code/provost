#!/bin/bash
## Name: chage-l
## Description: Extract password-aging fields from `chage -l`
## Version: 1.0
## Priority: 22
## Sample: samples/chage-l/basic.txt

# `chage -l <user>` prints "Key   : Value" lines (note the space before the
# colon). Emit a single record with one field per line.

_chage_is_line () {
    [[ "$1" =~ ^[A-Za-z][^:]*[[:space:]]:[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Require the distinctive "Last password change" key to avoid matching any
    # generic "key : value" output.
    [[ "$text" == *"Last password change"*":"* ]] || return 1
    local line
    while IFS= read -r line; do
        if _chage_is_line "$line"; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done <<< "$text"
    return 1
}

_chage_snake () {
    local s="$1"
    s="$(printf '%s' "$s" | tr 'A-Z' 'a-z')"
    s="${s// /_}"
    # keep only [a-z0-9_]
    local out="" c i
    for ((i=0; i<${#s}; i++)); do
        c="${s:$i:1}"
        case "$c" in
            [a-z0-9_]) out+="$c" ;;
        esac
    done
    printf '%s' "$out"
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        _chage_is_line "$line" || continue
        local key="${line%%:*}"
        local value="${line#*: }"
        # trim trailing whitespace from key
        key="${key%"${key##*[![:space:]]}"}"
        # trim leading whitespace from value
        value="${value#"${value%%[![:space:]]*}"}"
        local field
        field="$(_chage_snake "$key")"
        [[ -z "$field" ]] && continue
        entry=1
        result+="entry1.${field} ${value}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
