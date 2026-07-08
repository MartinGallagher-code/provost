#!/bin/bash
## Name: vmstat-a
## Description: Extract per-sample rows from `vmstat -a` (active/inactive memory) output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/vmstat-a/basic.txt

# `vmstat -a` prints a two-line banner+header:
#   procs -----------memory---------- ---swap-- ...
#    r  b   swpd   free  inact active   si   so   bi   bo   in   cs us sy id wa st
# followed by one sample row per line. The distinguishing signature vs plain
# `vmstat` is the "inact"/"active" memory columns (plain vmstat shows buff/cache).
# Emit ONE record per sample row; skip both header lines.

_vmstat_a_sanitize () {
    local v="$1"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *procs* ]]  || return 1
    [[ "$text" == *inact* ]]  || return 1
    [[ "$text" == *active* ]] || return 1
    [[ "$text" == *swpd* ]]   || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line idx=0 i
    local -a hdr=() t=()
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        [[ $idx -eq 1 ]] && continue          # banner
        if [[ $idx -eq 2 ]]; then             # column header
            read -ra hdr <<< "$line"
            continue
        fi
        read -ra t <<< "$line"
        [[ ${#t[@]} -eq ${#hdr[@]} ]] || continue
        entry=$((entry + 1))
        for ((i=0; i<${#hdr[@]}; i++)); do
            result+="entry${entry}.$(_vmstat_a_sanitize "${hdr[$i]}") $(_vmstat_a_sanitize "${t[$i]}")"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
