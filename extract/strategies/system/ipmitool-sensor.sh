#!/bin/bash
## Name: ipmitool-sensor
## Description: Extract sensor rows from `ipmitool sensor`
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/ipmitool-sensor/basic.txt

# `ipmitool sensor` prints one "|"-delimited row per sensor with 10 fields:
#   name | reading | unit | status | lnr | lcr | lnc | unc | ucr | unr
# Emit ONE record per sensor row.

_it_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }
_it_trim () {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line n=0 c
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        c="${line//[^|]/}"
        [[ ${#c} -eq 9 ]] && n=$((n + 1))
    done <<< "$text"
    [[ $n -ge 3 ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line c
    local -a t
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        c="${line//[^|]/}"
        [[ ${#c} -eq 9 ]] || continue
        IFS='|' read -ra t <<< "$line"
        [[ ${#t[@]} -eq 10 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.name $(_it_san "$(_it_trim "${t[0]}")")"$'\n'
        result+="entry${entry}.reading $(_it_san "$(_it_trim "${t[1]}")")"$'\n'
        result+="entry${entry}.unit $(_it_san "$(_it_trim "${t[2]}")")"$'\n'
        result+="entry${entry}.status $(_it_san "$(_it_trim "${t[3]}")")"$'\n'
        result+="entry${entry}.lower_nr $(_it_san "$(_it_trim "${t[4]}")")"$'\n'
        result+="entry${entry}.lower_crit $(_it_san "$(_it_trim "${t[5]}")")"$'\n'
        result+="entry${entry}.lower_noncrit $(_it_san "$(_it_trim "${t[6]}")")"$'\n'
        result+="entry${entry}.upper_noncrit $(_it_san "$(_it_trim "${t[7]}")")"$'\n'
        result+="entry${entry}.upper_crit $(_it_san "$(_it_trim "${t[8]}")")"$'\n'
        result+="entry${entry}.upper_nr $(_it_san "$(_it_trim "${t[9]}")")"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
