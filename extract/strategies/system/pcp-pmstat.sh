#!/bin/bash
## Name: pcp-pmstat
## Description: Extract per-sample rows from `pcp pmstat` / `pmstat` columnar output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/pcp-pmstat/basic.txt

# `pcp pmstat` prints a two-line banner+header:
#    loadavg           memory      swap        io    system         cpu
#    1 min  swpd  free  buff cache  si so  bi bo  in cs  us sy id
# followed by one sample row per line. The leading "loadavg / 1 min" column is a
# single float value (e.g. 0.42), so data rows carry 14 fixed columns. Signature:
# the "loadavg" group banner plus the "1 min" sub-header. Emit ONE record per
# sample row; skip both header lines.

_pcp_sanitize () {
    local v="$1"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *loadavg* ]] || return 1
    [[ "$text" == *swpd* ]]    || return 1
    [[ "$text" == *"1 min"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line i
    local -a t=()
    local -a fields=(loadavg swpd free buff cache si so bi bo in cs us sy id)
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra t <<< "$line"
        # data rows: first token is a float (loadavg), header rows are not
        [[ "${t[0]}" =~ ^[0-9]+\.[0-9]+$ ]] || continue
        [[ ${#t[@]} -eq ${#fields[@]} ]] || continue
        entry=$((entry + 1))
        for ((i=0; i<${#fields[@]}; i++)); do
            result+="entry${entry}.${fields[$i]} $(_pcp_sanitize "${t[$i]}")"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
