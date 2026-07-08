#!/bin/bash
## Name: vmstat-w
## Description: Extract per-sample rows from `vmstat -w` (wide) output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/vmstat-w/basic.txt

# `vmstat -w` prints the same fields as plain vmstat but in a wide layout with a
# two-line banner+header:
#   procs -----------------------memory---------------------- ---swap-- ...
#      r    b         swpd         free         buff        cache   si ...
# followed by one sample row per line. The distinguishing signature vs plain
# `vmstat` is the very long dash run in the memory banner (wide format only).
# Emit ONE record per sample row; skip both header lines.

_vmstat_w_sanitize () {
    local v="$1"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *procs* ]]                     || return 1
    [[ "$text" == *swpd* ]]                       || return 1
    # Wide layout: a long dash run precedes "memory" (plain vmstat has ~11 dashes).
    [[ "$text" == *"-----------------memory"* ]]  || return 1
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
            result+="entry${entry}.$(_vmstat_w_sanitize "${hdr[$i]}") $(_vmstat_w_sanitize "${t[$i]}")"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
