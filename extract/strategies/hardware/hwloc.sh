#!/bin/bash
## Name: hwloc
## Description: Extract hardware topology from hwloc lstopo text output
## Version: 1.0
## Priority: 15
## Sample: samples/hwloc/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    _is_json "$1" && return 1
    local matches=0
    [[ "$text" == *"Machine"* ]] && matches=$((matches + 1))
    [[ "$text" == *"Package"* ]] && matches=$((matches + 1))
    [[ "$text" == *"NUMANode"* ]] && matches=$((matches + 1))
    [[ "$text" == *"Core "* ]] && matches=$((matches + 1))
    [[ "$text" == *"PU "* ]] && matches=$((matches + 1))
    [[ "$text" == *"L3 "* || "$text" == *"L2 "* ]] && matches=$((matches + 1))
    # Need at least 3 matches to be confident this is hwloc output
    if [[ $matches -ge 3 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local num_packages=0
    local num_numa_nodes=0
    local num_cores=0
    local num_pus=0
    local machine_memory=""
    local current_pkg=0

    # Regex patterns with parentheses stored in variables (bash requires this)
    local re_machine='Machine[[:space:]]*[(]([^)]+)[)]'
    local re_package='Package[[:space:]]+(L|P)#([0-9]+)'
    local re_numa='NUMANode[[:space:]]+(L|P)#([0-9]+)'
    local re_numa_mb='[(]([0-9]+)MB[)]'
    local re_numa_mb2='[(]P#[0-9]+[[:space:]]+([0-9]+)MB[)]'
    local re_numa_gb='[(]([0-9]+)GB[)]'
    local re_numa_gb2='[(]P#[0-9]+[[:space:]]+([0-9]+)GB[)]'
    local re_l3='L3[[:space:]]+[(]([^)]+)[)]'
    local re_l2='L2[[:space:]]+[(]([^)]+)[)]'
    local re_l1d='L1d[[:space:]]+[(]([^)]+)[)]'
    local re_l1i='L1i[[:space:]]+[(]([^)]+)[)]'
    local re_core='Core[[:space:]]+(L|P)#([0-9]+)'
    local re_pu='PU[[:space:]]+(L|P)#([0-9]+)'

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Machine line: "Machine (128GB total)"
        if [[ "$line" =~ $re_machine ]]; then
            machine_memory="${BASH_REMATCH[1]}"
            result+="machine_memory ${machine_memory}"$'\n'
            continue
        fi

        # Package line: "Package L#0" or "Package P#0"
        if [[ "$line" =~ $re_package ]]; then
            num_packages=$((num_packages + 1))
            current_pkg="${BASH_REMATCH[2]}"
            continue
        fi

        # NUMANode line: "NUMANode L#0 (P#0 32168MB)"
        if [[ "$line" =~ $re_numa ]]; then
            num_numa_nodes=$((num_numa_nodes + 1))
            # Extract memory if present
            if [[ "$line" =~ $re_numa_mb ]]; then
                result+="numa${num_numa_nodes}.memory_MB ${BASH_REMATCH[1]}"$'\n'
            elif [[ "$line" =~ $re_numa_mb2 ]]; then
                result+="numa${num_numa_nodes}.memory_MB ${BASH_REMATCH[1]}"$'\n'
            fi
            if [[ "$line" =~ $re_numa_gb ]]; then
                result+="numa${num_numa_nodes}.memory_GB ${BASH_REMATCH[1]}"$'\n'
            elif [[ "$line" =~ $re_numa_gb2 ]]; then
                result+="numa${num_numa_nodes}.memory_GB ${BASH_REMATCH[1]}"$'\n'
            fi
            continue
        fi

        # L3 cache: "L3 (32MB)"
        if [[ "$line" =~ $re_l3 ]]; then
            result+="package${current_pkg}.l3_cache ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # L2 cache: "L2 (256KB)"
        if [[ "$line" =~ $re_l2 ]]; then
            result+="package${current_pkg}.l2_cache ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # L1d cache: "L1d (32KB)"
        if [[ "$line" =~ $re_l1d ]]; then
            result+="package${current_pkg}.l1d_cache ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # L1i cache: "L1i (32KB)"
        if [[ "$line" =~ $re_l1i ]]; then
            result+="package${current_pkg}.l1i_cache ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Core line: "Core L#0" or "Core P#0"
        if [[ "$line" =~ $re_core ]]; then
            num_cores=$((num_cores + 1))
            continue
        fi

        # PU (processing unit) line: "PU L#0" or "PU P#0"
        if [[ "$line" =~ $re_pu ]]; then
            num_pus=$((num_pus + 1))
            continue
        fi
    done <<< "$text"

    result+="num_packages ${num_packages}"$'\n'
    result+="num_numa_nodes ${num_numa_nodes}"$'\n'
    result+="num_cores ${num_cores}"$'\n'
    result+="num_pus ${num_pus}"$'\n'

    echo "$result"
}
