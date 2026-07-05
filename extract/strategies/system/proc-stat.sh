#!/bin/bash
## Name: proc-stat
## Description: Extract fields from /proc-style key: value files with numeric values and units
## Version: 1.0
## Priority: 25
## Sample: samples/proc-stat/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Repeated top-level keys => a multi-record output; leave it to the dedicated
    # record strategy rather than flattening it into one wide row.
    _has_repeated_top_keys "$text" && return 1
    # Match lines with pattern: AlphaKey: number (with optional unit)
    # Need at least 2 matching lines to distinguish from generic colons
    local match_count=0
    while IFS= read -r _line; do
        [[ "$_line" =~ ^[A-Za-z][A-Za-z0-9_]*:\ *[0-9] ]] && match_count=$((match_count + 1))
    done <<< "$text"
    [[ $match_count -ge 2 ]]
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Must match key: number pattern
        [[ "$line" =~ ^[A-Za-z][A-Za-z0-9_]*:\ *[0-9] ]] || continue

        local key value
        key=$(_strat_proc_stat_extract_key "$line")
        value=$(_strat_proc_stat_extract_value "$line")

        [[ -z "$key" ]] && continue
        [[ -z "$value" ]] && continue

        result+="${key} ${value}"$'\n'
    done <<< "$text"

    echo "$result"
}

_strat_proc_stat_extract_key () {
    local line="$1"
    echo "${line%%:*}"
}

_strat_proc_stat_extract_value () {
    local line="$1"
    # Get everything after the colon, trim leading whitespace
    local raw="${line#*:}"
    while [[ "$raw" == " "* ]]; do raw="${raw# }"; done
    # Replace spaces with underscores (e.g., "16384000 kB" -> "16384000_kB")
    raw="${raw// /_}"
    # Strip leading/trailing underscores
    raw="${raw#_}"
    raw="${raw%_}"
    echo "$raw"
}
