#!/bin/bash
## Name: psql-pg-stat-bgwriter
## Description: Extract pg_stat_bgwriter fields from psql expanded output
## Version: 1.0
## Priority: 9
## Sample: samples/psql-pg-stat-bgwriter/basic.txt

# psql `\x` expanded output for pg_stat_bgwriter:
#   -[ RECORD 1 ]---------+------------------------------
#   checkpoints_timed     | 8452
#   buffers_checkpoint    | 4451200
# Flatten the `key | value` rows into ONE wide record (`entry1.<key> value`).

_psqlbg_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"-[ RECORD 1 ]"* ]] || return 1
    [[ "$text" == *"checkpoints_timed"* || "$text" == *"buffers_checkpoint"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" line key val fields=0
    while IFS= read -r line; do
        case "$line" in
            *-\[\ RECORD*) continue ;;   # record separator
        esac
        # `key | value` rows.
        [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\|[[:space:]]*(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        val="${val%"${val##*[![:space:]]}"}"   # rtrim
        result+="entry1.${key} $(_psqlbg_san "$val")"$'\n'
        fields=$((fields + 1))
    done <<< "$text"
    [[ $fields -gt 0 ]] && result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
