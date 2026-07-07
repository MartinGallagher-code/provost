#!/bin/bash
## Name: nodetool-status
## Description: Extract node rows from `nodetool status`
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/nodetool-status/basic.txt

# `nodetool status` prints a Datacenter banner, a "Status=Up/Down" legend, then
# an aligned table headed `--  Address  Load  Tokens  Owns (effective)  Host ID
# Rack`. Each data row starts with a 2-char status code (U/D + N/L/J/M) and the
# Load column is "<num> <unit>" (two tokens). Emit ONE record per node row.

_ns_san () { local v="$1"; v="${v//$'\t'/_}"; v="${v// /_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"Status=Up/Down"* ]]     || return 1
    [[ "$text" == *"Host ID"* ]]            || return 1
    [[ "$text" == *"-- "*"Address"* ]]      || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line
    local -a t
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -eq 8 ]] || continue
        [[ "${t[0]}" =~ ^[UD][NLJM]$ ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.status ${t[0]}"$'\n'
        result+="entry${entry}.address ${t[1]}"$'\n'
        result+="entry${entry}.load $(_ns_san "${t[2]} ${t[3]}")"$'\n'
        result+="entry${entry}.tokens ${t[4]}"$'\n'
        result+="entry${entry}.owns ${t[5]}"$'\n'
        result+="entry${entry}.host_id ${t[6]}"$'\n'
        result+="entry${entry}.rack ${t[7]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
