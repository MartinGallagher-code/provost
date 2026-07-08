#!/bin/bash
## Name: es-cat-allocation
## Description: Extract node rows from Elasticsearch `_cat/allocation`
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/es-cat-allocation/basic.txt

# Elasticsearch `_cat/allocation?v` prints an aligned table headed `shards
# disk.indices disk.used disk.avail disk.total disk.percent host ip node`. Each
# data row has 9 whitespace tokens whose first cell is an integer shard count.
# Emit ONE record per node row; skip the header.

_ea_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"disk.indices"* ]] || return 1
    [[ "$text" == *"disk.avail"* ]]   || return 1
    [[ "$text" == *"shards"* ]]       || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line
    local -a t
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -eq 9 ]] || continue
        [[ "${t[0]}" =~ ^[0-9]+$ ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.shards ${t[0]}"$'\n'
        result+="entry${entry}.disk_indices ${t[1]}"$'\n'
        result+="entry${entry}.disk_used ${t[2]}"$'\n'
        result+="entry${entry}.disk_avail ${t[3]}"$'\n'
        result+="entry${entry}.disk_total ${t[4]}"$'\n'
        result+="entry${entry}.disk_percent ${t[5]}"$'\n'
        result+="entry${entry}.host ${t[6]}"$'\n'
        result+="entry${entry}.ip ${t[7]}"$'\n'
        result+="entry${entry}.node ${t[8]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
