#!/bin/bash
## Name: cuda-bandwidthtest
## Description: Extract bandwidth metrics from NVIDIA CUDA bandwidth test output
## Version: 1.0
## Priority: 12
## Sample: samples/cuda-bandwidthtest/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Primary: explicit CUDA Bandwidth Test header
    if [[ "$text" == *"CUDA Bandwidth Test"* ]]; then
        return 0
    fi

    # Secondary: all three bandwidth direction headers + bandwidth unit
    if [[ "$text" == *"Host to Device Bandwidth"* ]] &&
       [[ "$text" == *"Device to Host Bandwidth"* ]] &&
       [[ "$text" == *"Bandwidth(GB/s)"* ]]; then
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_direction=""
    local device_name=""
    local memory_type=""
    local test_result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Device name: " Device 0: Tesla V100-SXM2-32GB"
        if [[ "$line" =~ ^[[:space:]]*Device\ [0-9]+: ]]; then
            device_name=$(_strat_cuda_bw_extract_device "$line")
            continue
        fi

        # Direction headers
        if [[ "$line" == *"Host to Device Bandwidth"* ]]; then
            current_direction="h2d"
            continue
        fi
        if [[ "$line" == *"Device to Host Bandwidth"* ]]; then
            current_direction="d2h"
            continue
        fi
        if [[ "$line" == *"Device to Device Bandwidth"* ]]; then
            current_direction="d2d"
            continue
        fi

        # Memory type: " PINNED Memory Transfers"
        if [[ "$line" =~ (PINNED|PAGEABLE)\ Memory\ Transfers ]]; then
            local _trimmed="$line"
            while [[ "$_trimmed" == " "* || "$_trimmed" == "	"* ]]; do _trimmed="${_trimmed#?}"; done
            read -ra _arr <<< "$_trimmed"
            memory_type="${_arr[0]}"
            continue
        fi

        # Data line: "   32000000                     12.4"
        # Skip header lines containing "Transfer Size" or "Bandwidth"
        if [[ "$line" == *"Transfer Size"* ]]; then
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+[0-9] ]]; then
            local _trimmed="$line"
            while [[ "$_trimmed" == " "* || "$_trimmed" == "	"* ]]; do _trimmed="${_trimmed#?}"; done
            read -ra _arr <<< "$_trimmed"
            local bw="${_arr[1]}"
            local sz="${_arr[0]}"
            if [[ -n "$bw" && -n "$current_direction" ]]; then
                case "$current_direction" in
                    h2d) result+="host_to_device_bandwidth_GB_per_s ${bw}"$'\n' ;;
                    d2h) result+="device_to_host_bandwidth_GB_per_s ${bw}"$'\n' ;;
                    d2d) result+="device_to_device_bandwidth_GB_per_s ${bw}"$'\n' ;;
                esac
                # Record transfer size from the last data line seen
                [[ -n "$sz" ]] && result+="transfer_size_bytes ${sz}"$'\n'
            fi
            continue
        fi

        # Result line: "Result = PASS"
        if [[ "$line" =~ ^Result[[:space:]]*= ]]; then
            test_result="${line##*= }"
            while [[ "$test_result" == " "* ]]; do test_result="${test_result# }"; done
            continue
        fi
    done <<< "$text"

    [[ -n "$device_name" ]] && result+="device_name ${device_name}"$'\n'
    [[ -n "$memory_type" ]] && result+="memory_type ${memory_type}"$'\n'
    [[ -n "$test_result" ]] && result+="result ${test_result}"$'\n'

    echo "$result"
}

_strat_cuda_bw_trim () {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    echo "$s"
}

_strat_cuda_bw_extract_device () {
    local line="$1"
    # Extract everything after "Device N: "
    local name="${line#*Device [0-9]*: }"
    # Use regex for more reliable extraction
    if [[ "$line" =~ Device\ [0-9]+:\ (.*) ]]; then
        name="${BASH_REMATCH[1]}"
    fi
    echo "$name"
}
