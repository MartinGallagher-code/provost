#!/bin/bash
## Name: docker-stats
## Description: Extract container resource usage from docker stats --no-stream output
## Version: 1.0
## Priority: 35
## Sample: samples/docker-stats/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    local found_header=0
    while IFS= read -r line; do
        if [[ "$line" == *"CONTAINER ID"* ]] && [[ "$line" == *"CPU %"* ]] && [[ "$line" == *"MEM USAGE"* ]]; then
            found_header=1
            break
        fi
    done <<< "$text"
    if [[ $found_header -eq 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local container_num=0
    local in_data=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect header line — skip it and start parsing data
        if [[ "$line" == *"CONTAINER ID"* ]] && [[ "$line" == *"CPU %"* ]]; then
            in_data=1
            continue
        fi

        if [[ $in_data -eq 1 ]]; then
            # Parse data row by splitting on whitespace
            # Format: CONTAINER_ID  NAME  CPU%  MEM_USAGE / MEM_LIMIT  MEM%  NET_I / NET_O  BLOCK_I / BLOCK_O  PIDS
            read -ra _arr <<< "$line"

            # Need at least: id name cpu% mem_usage / mem_limit mem% net_i / net_o block_i / block_o pids
            # Indices:        0  1    2   3          4 5         6    7     8 9     10      11 12      13
            [[ ${#_arr[@]} -lt 13 ]] && continue

            local name="${_arr[1]}"
            local cpu="${_arr[2]}"
            local mem_usage="${_arr[3]}"
            # _arr[4] is "/"
            local mem_limit="${_arr[5]}"
            local mem_pct="${_arr[6]}"
            # _arr[7] is net_in, _arr[8] is "/", _arr[9] is net_out
            # _arr[10] is block_in, _arr[11] is "/", _arr[12] is block_out
            local pids="${_arr[13]}"

            # If there are fewer elements, try to detect pids at last position
            if [[ -z "$pids" ]]; then
                pids="${_arr[${#_arr[@]}-1]}"
            fi

            container_num=$((container_num + 1))
            local prefix="container${container_num}_"

            result+="${prefix}name ${name}"$'\n'
            result+="${prefix}cpu ${cpu}"$'\n'
            result+="${prefix}mem_usage ${mem_usage}"$'\n'
            result+="${prefix}mem_limit ${mem_limit}"$'\n'
            result+="${prefix}mem_pct ${mem_pct}"$'\n'
            [[ -n "$pids" ]] && result+="${prefix}pids ${pids}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
