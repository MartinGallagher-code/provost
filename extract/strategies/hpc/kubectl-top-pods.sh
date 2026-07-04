#!/bin/bash
## Name: kubectl-top-pods
## Description: Extract pod resource usage from kubectl top pods output
## Version: 1.0
## Priority: 22
## Technique: table
## Sample: samples/kubectl-top-pods/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$text" && return 1
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    # kubectl top pods header: NAME  CPU(cores)  MEMORY(bytes)
    # or with namespace: NAMESPACE  NAME  CPU(cores)  MEMORY(bytes)
    if [[ "$first_line" == "NAME"* && "$first_line" == *"CPU(cores)"* && "$first_line" == *"MEMORY(bytes)"* ]]; then
        return 0
    fi
    if [[ "$first_line" == "NAMESPACE"* && "$first_line" == *"CPU(cores)"* && "$first_line" == *"MEMORY(bytes)"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local pod_n=0
    local past_header=0
    local has_namespace=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == *"CPU(cores)"* && "$line" == *"MEMORY(bytes)"* ]]; then
            past_header=1
            [[ "$line" == "NAMESPACE"* ]] && has_namespace=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        read -ra _arr <<< "$line"

        pod_n=$((pod_n + 1))
        local prefix="pod${pod_n}"

        if [[ $has_namespace -eq 1 ]]; then
            [[ ${#_arr[@]} -lt 4 ]] && continue
            local ns="${_arr[0]}"
            local name="${_arr[1]}"
            local cpu="${_arr[2]}"
            local mem="${_arr[3]}"
            result+="${prefix}.namespace ${ns}"$'\n'
            result+="${prefix}.name ${name}"$'\n'
            result+="${prefix}.cpu ${cpu}"$'\n'
            result+="${prefix}.memory ${mem}"$'\n'
        else
            [[ ${#_arr[@]} -lt 3 ]] && continue
            local name="${_arr[0]}"
            local cpu="${_arr[1]}"
            local mem="${_arr[2]}"
            result+="${prefix}.name ${name}"$'\n'
            result+="${prefix}.cpu ${cpu}"$'\n'
            result+="${prefix}.memory ${mem}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
