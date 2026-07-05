#!/bin/bash
## Name: numactl
## Description: Extract NUMA topology from numactl --hardware output
## Version: 1.0
## Priority: 10
## Sample: samples/numactl/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$1" && return 1
    if [[ "$text" == *"available:"* ]] && [[ "$text" == *"node"* ]] && \
       [[ "$text" == *"cpus:"* || "$text" == *"size:"* ]]; then
        return 0
    fi
    if [[ "$text" == *"node distances"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_distances=0
    local dist_row=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # "available: 2 nodes (0-1)"
        if [[ "$line" =~ ^available:[[:space:]]*([0-9]+)[[:space:]]*node ]]; then
            result+="num_nodes ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # "node 0 cpus: 0 1 2 3 4 5"
        if [[ "$line" =~ ^node[[:space:]]+([0-9]+)[[:space:]]+cpus:[[:space:]]*(.*) ]]; then
            local node_id="${BASH_REMATCH[1]}"
            local cpus="${BASH_REMATCH[2]}"
            while [[ "$cpus" == *" " ]]; do cpus="${cpus% }"; done
            result+="node${node_id}.cpus ${cpus}"$'\n'
            continue
        fi

        # "node 0 size: 32168 MB"
        if [[ "$line" =~ ^node[[:space:]]+([0-9]+)[[:space:]]+size:[[:space:]]*([0-9]+)[[:space:]]*MB ]]; then
            result+="node${BASH_REMATCH[1]}.size_MB ${BASH_REMATCH[2]}"$'\n'
            continue
        fi

        # "node 0 free: 30124 MB"
        if [[ "$line" =~ ^node[[:space:]]+([0-9]+)[[:space:]]+free:[[:space:]]*([0-9]+)[[:space:]]*MB ]]; then
            result+="node${BASH_REMATCH[1]}.free_MB ${BASH_REMATCH[2]}"$'\n'
            continue
        fi

        # "node distances:"
        if [[ "$line" == *"node distances"* ]]; then
            in_distances=1
            dist_row=0
            continue
        fi

        # Distance matrix header: "node   0   1"
        if [[ $in_distances -eq 1 && "$line" =~ ^node[[:space:]] ]]; then
            # Skip header row
            continue
        fi

        # Distance matrix row: "  0:  10  21"
        if [[ $in_distances -eq 1 && "$line" =~ ^[[:space:]]*([0-9]+):[[:space:]]*(.*) ]]; then
            local from_node="${BASH_REMATCH[1]}"
            local distances="${BASH_REMATCH[2]}"
            while [[ "$distances" == *" " ]]; do distances="${distances% }"; done
            # Normalize whitespace
            distances=$(echo "$distances" | tr -s ' ')
            result+="distance.from${from_node} ${distances}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
