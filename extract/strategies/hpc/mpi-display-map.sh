#!/bin/bash
## Name: mpi-display-map
## Description: Extract process mapping from Open MPI --display-map output
## Version: 1.0
## Priority: 15
## Sample: samples/mpi-display-map/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Primary detection: Open MPI display-map header
    if [[ "$text" == *"Display the map"* ]]; then
        return 0
    fi

    # Data for node section
    if [[ "$text" == *"Data for node"* && "$text" == *"Num procs"* ]]; then
        return 0
    fi

    # mapped_node XML-style tag from Open MPI
    if [[ "$text" == *"mapped_node"* && "$text" == *"slot"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi

    # Num nodes header
    if [[ "$text" == *"Num nodes"* && "$text" == *"Num procs"* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local num_nodes=0
    local total_procs=0
    local current_node=""
    local node_proc_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # "Num nodes: 4"
        if [[ "$line" =~ [Nn]um[[:space:]]+nodes[[:space:]]*[:=][[:space:]]*([0-9]+) ]]; then
            num_nodes="${BASH_REMATCH[1]}"
            result+="num_nodes ${num_nodes}"$'\n'
            continue
        fi

        # "Data for node: compute01   Num procs: 4"
        if [[ "$line" =~ "Data for node"[[:space:]]*:[[:space:]]*([^[:space:]]+) ]]; then
            # Flush previous node
            if [[ -n "$current_node" ]]; then
                result+="node.${current_node}.num_procs ${node_proc_count}"$'\n'
            fi
            current_node="${BASH_REMATCH[1]}"
            node_proc_count=0
            num_nodes=$((num_nodes + 1))

            if [[ "$line" =~ [Nn]um[[:space:]]+procs[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                node_proc_count="${BASH_REMATCH[1]}"
                total_procs=$((total_procs + node_proc_count))
            fi
            result+="node.${current_node}.name ${current_node}"$'\n'
            continue
        fi

        # Process/rank line: "Rank 0: slot=0, binding=0001"
        # Or: "Process OMPI_COMM rank: 0  bound: socket 0[core 0]"
        if [[ "$line" =~ [Rr]ank[[:space:]]+([0-9]+) ]]; then
            local rank="${BASH_REMATCH[1]}"
            local slot=""
            local binding=""

            if [[ "$line" =~ slot[[:space:]]*[:=][[:space:]]*([^,[:space:]]+) ]]; then
                slot="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ bind(ing)?[[:space:]]*[:=][[:space:]]*([^,[:space:]]+) ]]; then
                binding="${BASH_REMATCH[2]}"
            fi
            if [[ "$line" =~ bound[[:space:]]*[:=][[:space:]]*(.*) ]]; then
                binding="${BASH_REMATCH[1]}"
            fi

            if [[ -n "$current_node" ]]; then
                result+="node.${current_node}.rank.${rank}.rank ${rank}"$'\n'
                [[ -n "$slot" ]] && result+="node.${current_node}.rank.${rank}.slot ${slot}"$'\n'
                [[ -n "$binding" ]] && result+="node.${current_node}.rank.${rank}.binding ${binding}"$'\n'
            else
                result+="rank.${rank}.rank ${rank}"$'\n'
                [[ -n "$slot" ]] && result+="rank.${rank}.slot ${slot}"$'\n'
                [[ -n "$binding" ]] && result+="rank.${rank}.binding ${binding}"$'\n'
            fi
            continue
        fi

        # mapped_node XML-style: <mapped_node name="node01" ...>
        if [[ "$line" =~ \<mapped_node[[:space:]]+name=\"([^\"]+)\" ]]; then
            if [[ -n "$current_node" ]]; then
                result+="node.${current_node}.num_procs ${node_proc_count}"$'\n'
            fi
            current_node="${BASH_REMATCH[1]}"
            node_proc_count=0
            num_nodes=$((num_nodes + 1))
            result+="node.${current_node}.name ${current_node}"$'\n'
            continue
        fi

        # <map_proc rank="0" slot="0:0"/>
        if [[ "$line" =~ \<map_proc[[:space:]] ]]; then
            local rank="" slot=""
            [[ "$line" =~ rank=\"([0-9]+)\" ]] && rank="${BASH_REMATCH[1]}"
            [[ "$line" =~ slot=\"([^\"]+)\" ]] && slot="${BASH_REMATCH[1]}"
            if [[ -n "$rank" && -n "$current_node" ]]; then
                node_proc_count=$((node_proc_count + 1))
                total_procs=$((total_procs + 1))
                result+="node.${current_node}.rank.${rank}.rank ${rank}"$'\n'
                [[ -n "$slot" ]] && result+="node.${current_node}.rank.${rank}.slot ${slot}"$'\n'
            fi
            continue
        fi

    done <<< "$text"

    # Flush last node
    if [[ -n "$current_node" && $node_proc_count -gt 0 ]]; then
        result+="node.${current_node}.num_procs ${node_proc_count}"$'\n'
    fi

    # Summary if we counted nodes but didn't get explicit num_nodes
    if [[ $num_nodes -gt 0 ]]; then
        # Only add if not already set from header
        if [[ "$result" != *"num_nodes "* ]]; then
            result+="num_nodes ${num_nodes}"$'\n'
        fi
    fi
    if [[ $total_procs -gt 0 ]]; then
        result+="total_procs ${total_procs}"$'\n'
    fi

    echo "$result"
}
