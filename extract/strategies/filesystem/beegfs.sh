#!/bin/bash
## Name: beegfs
## Description: Extract BeeGFS filesystem info from beegfs-ctl output
## Version: 1.0
## Priority: 15
## Sample: samples/beegfs/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1
    # BeeGFS markers
    if [[ "$text" == *"BeeGFS"* ]] || [[ "$text" == *"beegfs"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Management"* && "$text" == *"Metadata"* && "$text" == *"Storage"* ]]; then
        if [[ "$text" == *"target"* || "$text" == *"Target"* ]]; then
            return 0
        fi
    fi
    if [[ "$text" == *"Storage target"* ]] || [[ "$text" == *"beegfs-ctl"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local target_num=0
    local section=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect section headers
        if [[ "$line" == *"Management"* ]]; then
            section="management"
        fi
        if [[ "$line" == *"Metadata"* && "$line" != *"target"* ]]; then
            section="metadata"
        fi

        # Parse storage target lines
        # Typical format: "TargetID  NodeID  State  Capacity  Free  ..."
        # or: "Storage targets:" header followed by target lines
        if [[ "$line" == *"Storage target"* || "$line" == *"storage target"* ]]; then
            section="storage"
            continue
        fi

        # Target ID lines: "   1   node01   Online   500G   200G"
        if [[ "$section" == "storage" ]]; then
            # Skip header/separator lines
            [[ "$line" == *"TargetID"* ]] && continue
            [[ "$line" == "="* || "$line" == "-"* ]] && continue

            # Parse target data lines
            read -ra _arr <<< "$line"
            if [[ ${#_arr[@]} -ge 2 ]]; then
                # Check if first field looks like a target ID (numeric)
                if [[ "${_arr[0]}" =~ ^[0-9]+$ ]]; then
                    target_num=$((target_num + 1))
                    result+="target${target_num}.target_id ${_arr[0]}"$'\n'
                    # State field (typically 3rd or after node)
                    if [[ ${#_arr[@]} -ge 3 ]]; then
                        result+="target${target_num}.state ${_arr[2]}"$'\n'
                    fi
                    if [[ ${#_arr[@]} -ge 4 ]]; then
                        result+="target${target_num}.capacity ${_arr[3]}"$'\n'
                    fi
                    if [[ ${#_arr[@]} -ge 5 ]]; then
                        result+="target${target_num}.free_space ${_arr[4]}"$'\n'
                    fi
                    continue
                fi
            fi
        fi

        # Key-value lines from beegfs-ctl --getentryinfo or similar
        if [[ "$line" == *"TargetID:"* ]]; then
            local val="${line##*: }"
            val="${val## }"
            target_num=$((target_num + 1))
            result+="target${target_num}.target_id ${val}"$'\n'
            continue
        fi
        if [[ "$line" == *"State:"* || "$line" == *"Reachability:"* ]]; then
            local val="${line##*: }"
            val="${val## }"
            [[ $target_num -gt 0 ]] && result+="target${target_num}.state ${val}"$'\n'
            continue
        fi
        if [[ "$line" == *"Capacity:"* ]]; then
            local val="${line##*: }"
            val="${val## }"
            [[ $target_num -gt 0 ]] && result+="target${target_num}.capacity ${val}"$'\n'
            continue
        fi
        if [[ "$line" == *"Free space:"* || "$line" == *"Free:"* ]]; then
            local val="${line##*: }"
            val="${val## }"
            [[ $target_num -gt 0 ]] && result+="target${target_num}.free_space ${val}"$'\n'
            continue
        fi
        if [[ "$line" == *"Sessions:"* || "$line" == *"sessions:"* ]]; then
            local val="${line##*: }"
            val="${val## }"
            result+="num_sessions ${val}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}
