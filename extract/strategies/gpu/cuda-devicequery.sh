#!/bin/bash
## Name: cuda-devicequery
## Description: Extract CUDA device properties from deviceQuery output
## Version: 1.0
## Priority: 10
## Sample: samples/cuda-devicequery/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    if [[ "$text" == *"deviceQuery"* ]] && [[ "$text" == *"CUDA"* ]]; then
        return 0
    fi
    if [[ "$text" == *"CUDA Device"* ]] && [[ "$text" == *"CUDA Capability"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Total amount of global memory"* ]] && [[ "$text" == *"CUDA Driver Version"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Device name: 'Device 0: "Tesla V100-SXM2-32GB"'
        if [[ "$line" =~ Device\ [0-9]+:[[:space:]]*\"([^\"]+)\" ]]; then
            result+="device_name ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # CUDA Capability Major/Minor: "CUDA Capability Major/Minor version number:    7.0"
        if [[ "$line" =~ CUDA\ Capability.*:[[:space:]]*([0-9]+\.[0-9]+) ]]; then
            result+="compute_capability ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Total global memory: "Total amount of global memory:                 32510 MBytes (34089730048 bytes)"
        if [[ "$line" =~ Total\ amount\ of\ global\ memory.*:[[:space:]]*([0-9]+[[:space:]]*[A-Za-z]+) ]]; then
            local val="${BASH_REMATCH[1]}"
            result+="total_global_memory ${val}"$'\n'
            continue
        fi

        # Multiprocessors: "(80) Multiprocessors, (64) CUDA Cores/MP:     5120 CUDA Cores"
        # Also handles "(080)" zero-padded format
        if [[ "$line" =~ \(0*([0-9]+)\)\ Multiprocessors ]]; then
            result+="multiprocessors ${BASH_REMATCH[1]}"$'\n'
            # Also extract total CUDA cores from same line
            if [[ "$line" =~ ([0-9]+)\ CUDA\ Cores$ ]]; then
                result+="cuda_cores ${BASH_REMATCH[1]}"$'\n'
            fi
            continue
        fi

        # GPU Max Clock rate: "GPU Max Clock rate:                            1530 MHz"
        if [[ "$line" =~ GPU\ Max\ Clock\ rate.*:[[:space:]]*([0-9]+)[[:space:]]*MHz ]]; then
            result+="gpu_clock_MHz ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Memory Clock rate: "Memory Clock rate:                             877 MHz"
        if [[ "$line" =~ Memory\ Clock\ rate.*:[[:space:]]*([0-9]+)[[:space:]]*MHz ]]; then
            result+="memory_clock_MHz ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Memory Bus Width: "Memory Bus Width:                              4096-bit"
        if [[ "$line" =~ Memory\ Bus\ Width.*:[[:space:]]*([0-9]+-bit) ]]; then
            result+="memory_bus_width ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # L2 Cache Size: "L2 Cache Size:                                 6291456 bytes"
        if [[ "$line" =~ L2\ Cache\ Size.*:[[:space:]]*(.+) ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val%"${val##*[![:space:]]}"}"
            result+="l2_cache_size ${val}"$'\n'
            continue
        fi

        # CUDA Driver Version: "CUDA Driver Version / Runtime Version          12.2 / 12.1"
        if [[ "$line" =~ CUDA\ Driver\ Version.*Runtime\ Version[[:space:]]*([0-9]+\.[0-9]+)[[:space:]]*/[[:space:]]*([0-9]+\.[0-9]+) ]]; then
            result+="cuda_driver_version ${BASH_REMATCH[1]}"$'\n'
            result+="cuda_runtime_version ${BASH_REMATCH[2]}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}
