#!/bin/bash
## Name: top-batch
## Description: Extract process rows from `top -b -n1` (batch mode) output
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/top-batch/basic.txt

# `top -b -n1` prints a summary block (top/Tasks/%Cpu/Mem/Swap lines), a blank
# line, then a process table:
#     PID USER   PR  NI  VIRT  RES  SHR S %CPU %MEM  TIME+ COMMAND
#    1843 mysql  20   0 ...  S  24.3  8.1 412:07.44 mysqld
# Signature: the "top - HH:MM:SS up" header + "Tasks:" + "%Cpu". Emit ONE record
# per process row; skip the summary block and the column header.

_top_batch_sanitize () {
    local v="$1"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"top - "* ]] || return 1
    [[ "$text" == *"Tasks:"* ]] || return 1
    [[ "$text" == *"%Cpu"* ]]   || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line in_table=0 i
    local -a t=()
    local -a fields=(pid user pr ni virt res shr s cpu mem time command)
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra t <<< "$line"
        if [[ "${t[0]}" == "PID" ]]; then         # process-table header
            in_table=1
            continue
        fi
        [[ $in_table -eq 1 ]] || continue         # still in summary block
        [[ ${#t[@]} -eq ${#fields[@]} ]] || continue
        entry=$((entry + 1))
        for ((i=0; i<${#fields[@]}; i++)); do
            result+="entry${entry}.${fields[$i]} $(_top_batch_sanitize "${t[$i]}")"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
