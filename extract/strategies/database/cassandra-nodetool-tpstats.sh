#!/bin/bash
## Name: cassandra-nodetool-tpstats
## Description: Extract thread-pool rows from `nodetool tpstats`
## Version: 1.0
## Priority: 26
## Sample: samples/cassandra-nodetool-tpstats/basic.txt

# `nodetool tpstats` starts with a thread-pool table:
#   Pool Name   Active  Pending  Completed  Blocked  All time blocked
#   ReadStage        0        0    1204853        0                 0
# followed by unrelated "Latencies ... dropped message types" and
# "Message type / Dropped" blocks. Emit ONE record per pool row (the 6-column
# rows whose last five columns are integers); the trailing blocks are ignored
# because they never form a 6-token row with five numeric fields.

_ctp_sanitize_val () {
    local v="$1"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Signature: the distinctive thread-pool header columns.
    [[ "$text" == *"Pool Name"* ]]        || return 1
    [[ "$text" == *"Completed"* ]]        || return 1
    [[ "$text" == *"All time blocked"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line ok i
    local -a t
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -eq 6 ]] || continue
        ok=1
        for i in 1 2 3 4 5; do
            [[ "${t[$i]}" =~ ^[0-9]+$ ]] || { ok=0; break; }
        done
        [[ $ok -eq 1 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.pool_name $(_ctp_sanitize_val "${t[0]}")"$'\n'
        result+="entry${entry}.active ${t[1]}"$'\n'
        result+="entry${entry}.pending ${t[2]}"$'\n'
        result+="entry${entry}.completed ${t[3]}"$'\n'
        result+="entry${entry}.blocked ${t[4]}"$'\n'
        result+="entry${entry}.all_time_blocked ${t[5]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
