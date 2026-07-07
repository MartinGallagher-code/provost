#!/bin/bash
## Name: ps-eo-custom
## Description: Extract process rows from custom-column `ps -eo pid,ppid,user,...` output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/ps-eo-custom/basic.txt

# A custom `ps -eo pid,ppid,user,pri,ni,pcpu,pmem,rss,stat,comm` table:
#   PID  PPID USER  PRI  NI %CPU %MEM   RSS STAT COMMAND
#  1843     1 mysql  19   0 24.3 8.1 662104 Ssl  mysqld
# The distinguishing signature vs plain `ps aux` is the PPID + PRI columns.
# Emit ONE record per process row; skip the header.

_ps_eo_sanitize () {
    local v="$1"
    v="${v//$'\t'/_}"
    v="${v// /_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *PPID* ]]   || return 1
    [[ "$text" == *PRI* ]]    || return 1
    [[ "$text" == *"%CPU"* ]] || return 1
    [[ "$text" == *STAT* ]]   || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a t=()
    local -a fields=(pid ppid user pri ni cpu mem rss stat command)
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra t <<< "$line"
        [[ "${t[0]}" == "PID" ]] && continue          # header
        [[ ${#t[@]} -eq ${#fields[@]} ]] || continue
        entry=$((entry + 1))
        local i
        for ((i=0; i<${#fields[@]}; i++)); do
            result+="entry${entry}.${fields[$i]} $(_ps_eo_sanitize "${t[$i]}")"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
