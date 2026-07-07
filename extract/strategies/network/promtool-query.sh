#!/bin/bash
## Name: promtool-query
## Description: Extract instant-vector samples from `promtool query instant`
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/promtool-query/basic.txt

# `promtool query instant` prints one line per sample:
#   metric{label="v",...} => <value> @[<timestamp>]
# Emit ONE record per sample line: the metric series (name+labels), the value,
# and the timestamp.

_pq_san () { local v="$1"; v="${v//$'\t'/_}"; v="${v// /_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *" => "* ]] || return 1
    [[ "$text" == *" @["* ]]  || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line metric rest value ts
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == *" => "* ]] || continue
        [[ "$line" == *" @["* ]]  || continue
        metric="${line%% => *}"
        rest="${line#* => }"
        value="${rest%% @[*}"
        ts="${rest##* @[}"
        ts="${ts%]}"
        entry=$((entry + 1))
        result+="entry${entry}.metric $(_pq_san "$metric")"$'\n'
        result+="entry${entry}.value $(_pq_san "$value")"$'\n'
        result+="entry${entry}.timestamp $(_pq_san "$ts")"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
