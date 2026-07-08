#!/bin/bash
## Name: kubectl-top
## Description: Extract resource usage from kubectl top nodes / kubectl top pods output
## Version: 1.0
## Priority: 22
## Technique: table
## Sample: samples/kubectl-top/sample1.txt

# `kubectl top nodes` and `kubectl top pods` are the same command family and were
# two near-identical strategies. Merged here: the header tells the two apart —
# `top nodes` has percentage columns (`NAME CPU(cores) CPU% MEMORY(bytes)
# MEMORY%`), `top pods` does not (`[NAMESPACE] NAME CPU(cores) MEMORY(bytes)`).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$text" && return 1
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"; break
    done <<< "$text"
    [[ "$first_line" == "NAME"* || "$first_line" == "NAMESPACE"* ]] || return 1
    [[ "$first_line" == *"CPU"* && "$first_line" == *"MEMORY"* ]] || return 1
    [[ "$first_line" == *"cores"* || "$first_line" == *"%"* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" n=0 past_header=0 mode="" has_namespace=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == *"CPU"* && "$line" == *"MEMORY"* && ( "$line" == "NAME"* || "$line" == "NAMESPACE"* ) ]]; then
            past_header=1
            if [[ "$line" == *"%"* ]]; then mode="nodes"; else mode="pods"; fi
            [[ "$line" == "NAMESPACE"* ]] && has_namespace=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        local _arr; read -ra _arr <<< "$line"
        if [[ "$mode" == "nodes" ]]; then
            [[ ${#_arr[@]} -lt 5 ]] && continue
            n=$((n + 1)); local p="node${n}"
            result+="${p}.name ${_arr[0]}"$'\n'
            result+="${p}.cpu_cores ${_arr[1]}"$'\n'
            result+="${p}.cpu_pct ${_arr[2]}"$'\n'
            result+="${p}.mem_bytes ${_arr[3]}"$'\n'
            result+="${p}.mem_pct ${_arr[4]}"$'\n'
        elif [[ $has_namespace -eq 1 ]]; then
            [[ ${#_arr[@]} -lt 4 ]] && continue
            n=$((n + 1)); local p="pod${n}"
            result+="${p}.namespace ${_arr[0]}"$'\n'
            result+="${p}.name ${_arr[1]}"$'\n'
            result+="${p}.cpu ${_arr[2]}"$'\n'
            result+="${p}.memory ${_arr[3]}"$'\n'
        else
            [[ ${#_arr[@]} -lt 3 ]] && continue
            n=$((n + 1)); local p="pod${n}"
            result+="${p}.name ${_arr[0]}"$'\n'
            result+="${p}.cpu ${_arr[1]}"$'\n'
            result+="${p}.memory ${_arr[2]}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
