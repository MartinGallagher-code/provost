#!/bin/bash
## Name: collectl
## Description: Extract per-sample rows from `collectl` columnar output (CPU/Disks/Network)
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/collectl/basic.txt

# `collectl` prints a two-line banner+header:
#   #<--------CPU--------><----------Disks-----------><--------Network-------->
#   #cpu sys inter  ctxsw KBRead  Reads KBWrit Writes   KBIn  PktIn  KBOut PktOut
# followed by one sample row per line. Signature: the "#<...CPU...>" banner plus
# the "ctxsw" column. Emit ONE record per sample row; skip both header lines.

_collectl_sanitize () {
    local v="$1"
    v="${v//$'\t'/_}"
    v="${v// /_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"#<"* ]]  || return 1
    [[ "$text" == *CPU* ]]   || return 1
    [[ "$text" == *ctxsw* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line idx=0 i first
    local -a hdr=() t=()
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        [[ $idx -eq 1 ]] && continue          # "#<...>" group banner
        if [[ $idx -eq 2 ]]; then             # "#cpu sys ..." column header
            read -ra hdr <<< "$line"
            # strip the leading '#' from the first header token
            first="${hdr[0]}"
            hdr[0]="${first#\#}"
            continue
        fi
        read -ra t <<< "$line"
        [[ ${#t[@]} -eq ${#hdr[@]} ]] || continue
        entry=$((entry + 1))
        for ((i=0; i<${#hdr[@]}; i++)); do
            result+="entry${entry}.$(_collectl_sanitize "${hdr[$i]}") $(_collectl_sanitize "${t[$i]}")"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
