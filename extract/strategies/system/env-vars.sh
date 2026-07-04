#!/bin/bash
## Name: env-vars
## Description: Extract environment variable assignments (KEY=value format)
## Version: 1.0
## Priority: 30
## Sample: samples/env-vars/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=45

    # Must have multiple lines matching KEY=value pattern
    local match_count=0
    local export_count=0
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
            match_count=$((match_count + 1))
        fi
        if [[ "$_line" =~ ^(export\ |declare\ -x\ )[A-Z_][A-Z0-9_]*= ]]; then
            export_count=$((export_count + 1))
        fi
    done <<< "$text"
    [[ $match_count -ge 2 ]] && return 0
    # Also detect export/declare -x prefix
    [[ $export_count -ge 2 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"

    local result=""
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Strip declare -x or export prefix
        if [[ "$line" == "declare -x "* ]]; then
            line="${line#declare -x }"
        elif [[ "$line" == "export "* ]]; then
            line="${line#export }"
        fi

        # Must match KEY=value pattern
        [[ "$line" =~ ^[A-Z_][A-Z0-9_]*= ]] || continue

        # Split on first = only
        local key value
        key="${line%%=*}"
        value="${line#*=}"

        # Skip if key or value is empty
        [[ -z "$key" ]] && continue
        [[ -z "$value" ]] && continue

        # Strip surrounding quotes from value
        if [[ "$value" == \"*\" ]]; then
            value="${value#\"}"
            value="${value%\"}"
        fi
        value="${value//\'/}"

        # Replace spaces in value with underscores
        value="${value// /_}"

        result+="${key} ${value}"$'\n'
    done <<< "$text"

    echo "$result"
}
