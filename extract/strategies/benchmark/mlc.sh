#!/bin/bash
## Name: mlc
## Description: Extract memory latency and bandwidth from Intel MLC output
## Version: 1.0
## Priority: 10
## Sample: samples/mlc/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"Intel(R) Memory Latency Checker"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Measuring idle latencies"* ]] && \
       [[ "$text" == *"Measuring Peak"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Idle Latencies section
    # "Measuring idle latencies (in ns)..."
    # "		Numa node"
    # "Numa node	     0"
    # "       0	  89.5"
    local in_idle=0
    local in_bandwidth=0
    local bw_section=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Section detection
        if [[ "$line" == *"Measuring idle latencies"* ]]; then
            in_idle=1
            in_bandwidth=0
            continue
        fi
        if [[ "$line" == *"Measuring Peak Injection Memory Bandwidths"* ]]; then
            in_idle=0
            in_bandwidth=1
            bw_section="peak"
            continue
        fi
        if [[ "$line" == *"Measuring Memory Bandwidths"* ]]; then
            in_idle=0
            in_bandwidth=1
            bw_section="sustained"
            continue
        fi
        if [[ "$line" == *"Measuring Loaded Latencies"* ]]; then
            in_idle=0
            in_bandwidth=0
            continue
        fi

        # Parse idle latency matrix: "       0	  89.5	 139.2"
        # Row N contains latencies from node N to all other nodes
        # Self-latency (diagonal) is at column node+2 (1-indexed awk)
        if [[ $in_idle -eq 1 ]]; then
            # Skip header lines
            [[ "$line" == *"Numa node"* ]] && continue

            if [[ "$line" =~ ^[[:space:]]*[0-9] ]]; then
                read -ra _arr <<< "$line"
                local node="${_arr[0]}"
                if [[ "$node" =~ ^[0-9]+$ ]]; then
                    # Self-latency is at index (node + 1) in 0-indexed array
                    local col=$((node + 1))
                    local self_latency="${_arr[$col]:-}"
                    if [[ "$self_latency" =~ ^[0-9] ]]; then
                        result+="node${node}.idle_latency_ns ${self_latency}"$'\n'
                    fi
                fi
            fi
            continue
        fi

        # Parse bandwidth data
        if [[ $in_bandwidth -eq 1 ]]; then
            # "ALL Coverage           Coverage:  Full"
            # "Numa node 0 - Sequential  : 45678.9"
            # or tabular: "ALL Reads :     45678.9"
            if [[ "$line" == *":"*[0-9]* ]]; then
                # Get value: everything after last colon, trimmed, first word
                local val="${line##*:}"
                while [[ "$val" == " "* ]]; do val="${val# }"; done
                read -ra _arr <<< "$val"
                val="${_arr[0]}"
                # Get label: everything before the last colon with trailing number
                local label="${line%:*}"
                # Remove trailing spaces and numeric value portion
                while [[ "$label" == " "* ]]; do label="${label# }"; done
                while [[ "$label" == *" " ]]; do label="${label% }"; done
                label="${label// /_}"
                if [[ "$val" =~ ^[0-9] ]] && [[ -n "$label" ]]; then
                    result+="${bw_section}.${label}_MB_per_s ${val}"$'\n'
                fi
            fi
        fi
    done <<< "$text"

    echo "$result"
}
