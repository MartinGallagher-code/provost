#!/bin/bash
## Name: zypper-info
## Description: Extract package fields from `zypper info` ("Field : value" block)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/zypper-info/basic.txt

# `zypper info <pkg>` prints a "Field    : value" block (note the space before
# and after the colon), with a couple of banner lines and an indented free-text
# Description. Emit ONE wide record with one field per "Field : value" line.

_zypperinfo_is_line () {
    [[ "$1" =~ ^[A-Za-z][^:]*[[:space:]]:[[:space:]] ]]
}

_zypperinfo_field () {
    local s; s="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
    local out="" i c
    for ((i=0; i<${#s}; i++)); do
        c="${s:$i:1}"
        case "$c" in
            [a-z0-9]) out+="$c" ;;
            *) out+="_" ;;
        esac
    done
    # collapse repeated underscores
    while [[ "$out" == *__* ]]; do out="${out//__/_}"; done
    out="${out#_}"; out="${out%_}"
    printf '%s' "$out"
}

_zypperinfo_sanitize_val () {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive banner emitted by `zypper info`.
    [[ "$text" == *"Information for package"* ]] || return 1
    local line
    while IFS= read -r line; do
        if _zypperinfo_is_line "$line"; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line key value field
    while IFS= read -r line; do
        _zypperinfo_is_line "$line" || continue
        key="${line%%:*}"
        value="${line#*: }"
        field="$(_zypperinfo_field "$key")"
        [[ -z "$field" ]] && continue
        entry=1
        result+="entry1.${field} $(_zypperinfo_sanitize_val "$value")"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
