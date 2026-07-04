#!/bin/bash
## Name: kubectl-top-nodes
## Description: Extract node resource usage from kubectl top nodes output
## Version: 1.0
## Priority: 22
## Technique: table
## Sample: samples/kubectl-top-nodes/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    _is_json "$text" && return 1
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    # kubectl top nodes header: NAME  CPU(cores)  CPU%  MEMORY(bytes)  MEMORY%
    if [[ "$first_line" == "NAME"* && "$first_line" == *"CPU"* && "$first_line" == *"MEMORY"* ]]; then
        # Distinguish from generic kubectl get by checking for "cores" or "%"
        if [[ "$first_line" == *"cores"* || "$first_line" == *"%"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local node_n=0
    local past_header=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == "NAME"* && "$line" == *"CPU"* && "$line" == *"MEMORY"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 5 ]] && continue

        node_n=$((node_n + 1))
        local prefix="node${node_n}"

        local name="${_arr[0]}"
        local cpu_cores="${_arr[1]}"
        local cpu_pct="${_arr[2]}"
        local mem_bytes="${_arr[3]}"
        local mem_pct="${_arr[4]}"

        result+="${prefix}.name ${name}"$'\n'
        result+="${prefix}.cpu_cores ${cpu_cores}"$'\n'
        result+="${prefix}.cpu_pct ${cpu_pct}"$'\n'
        result+="${prefix}.mem_bytes ${mem_bytes}"$'\n'
        result+="${prefix}.mem_pct ${mem_pct}"$'\n'
    done <<< "$text"

    echo "$result"
}
