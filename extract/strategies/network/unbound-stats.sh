#!/bin/bash
## Name: unbound-stats
## Description: Extract counters from `unbound-control stats`
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/unbound-stats/basic.txt

# `unbound-control stats` prints one "key=value" counter per line, keys are dotted
# (e.g. total.num.queries=234567). This is a key/value snapshot: emit a single
# wide record `entry1.<key> value` for every counter, then total_entries 1.

_us_san () { local v="$1"; v="${v//$'\t'/_}"; v="${v// /_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"total.num.queries="* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" n=0 line key val
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == *"="* ]] || continue
        key="${line%%=*}"
        val="${line#*=}"
        key="${key//[[:space:]]/_}"
        [[ -n "$key" ]] || continue
        n=$((n + 1))
        result+="entry1.${key} $(_us_san "$val")"$'\n'
    done <<< "$text"
    [[ $n -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
