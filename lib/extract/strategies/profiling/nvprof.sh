#!/bin/bash
## Name: nvprof
## Description: Extract GPU profiling data from nvprof / Nsight Systems summary output
## Version: 1.0
## Priority: 25
## Sample: samples/nvprof/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong: nvprof or Nsight
    if [[ "$text" == *"nvprof"* ]] || [[ "$text" == *"Nsight"* ]]; then
        return 0
    fi
    # Detect by GPU activities section pattern
    if [[ "$text" == *"GPU activities"* ]]; then
        return 0
    fi
    # Detect CUDA profiling output patterns
    local indicator_count=0
    if [[ "$text" == *"CUDA"* ]]; then indicator_count=$((indicator_count + 1)); fi
    if [[ "$text" == *"API calls"* ]]; then indicator_count=$((indicator_count + 1)); fi
    if [[ "$text" == *"GPU activities"* ]]; then indicator_count=$((indicator_count + 1)); fi
    if [[ "$text" == *"memcpy"* ]] || [[ "$text" == *"Memcpy"* ]]; then indicator_count=$((indicator_count + 1)); fi
    if [[ "$text" == *"kernel"* ]] && [[ "$text" == *"Time(%)"* ]]; then indicator_count=$((indicator_count + 1)); fi
    # Need CUDA + at least one profiling pattern
    [[ $indicator_count -ge 2 ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local section=""
    local kernel_n=0
    local api_n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect section headers
        if [[ "$line" == *"GPU activities"* ]]; then
            section="gpu"
            continue
        fi
        if [[ "$line" == *"API calls"* ]]; then
            section="api"
            continue
        fi

        # GPU utilization
        if [[ "$line" == *"GPU utilization"* ]] || [[ "$line" == *"GPU Utilization"* ]]; then
            local val
            val=$(_strat_nvprof_extract_value "$line")
            [[ -n "$val" ]] && result+="gpu_utilization ${val}"$'\n'
            continue
        fi

        # Skip column headers
        if [[ "$line" == *"Time(%)"* ]] && [[ "$line" == *"Calls"* ]]; then
            continue
        fi

        # Parse data rows: "  42.86%  1.2345s    100    12.345us  kernel_name"
        # or: "  42.86%  1.2345ms    100    kernel_name"
        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 2 ]] && continue

        # Check if first field is a percentage
        if [[ "${_arr[0]}" =~ ^[0-9]+\.?[0-9]*%$ ]]; then
            local time_pct="${_arr[0]}"
            time_pct="${time_pct%%%}"
            # Last field is the name (kernel or API call)
            local name="${_arr[${#_arr[@]}-1]}"
            # Time is typically second field
            local time_val="${_arr[1]}"

            if [[ "$section" == "gpu" ]]; then
                kernel_n=$((kernel_n + 1))
                result+="kernel${kernel_n}_name ${name}"$'\n'
                result+="kernel${kernel_n}_time_pct ${time_pct}"$'\n'
                result+="kernel${kernel_n}_time ${time_val}"$'\n'

                # Check for memcpy
                if [[ "$name" == *"memcpy"* ]] || [[ "$name" == *"Memcpy"* ]]; then
                    result+="memcpy_time ${time_val}"$'\n'
                    result+="memcpy_time_pct ${time_pct}"$'\n'
                fi

                # Extract calls if present
                if [[ ${#_arr[@]} -ge 4 ]] && [[ "${_arr[2]}" =~ ^[0-9]+$ ]]; then
                    result+="kernel${kernel_n}_calls ${_arr[2]}"$'\n'
                fi
            elif [[ "$section" == "api" ]]; then
                api_n=$((api_n + 1))
                result+="api${api_n}_name ${name}"$'\n'
                result+="api${api_n}_time_pct ${time_pct}"$'\n'
                result+="api${api_n}_time ${time_val}"$'\n'
            fi
        fi
    done <<< "$text"

    # Compute total API call time if we have entries
    if [[ $api_n -gt 0 ]]; then
        result+="api_call_count ${api_n}"$'\n'
    fi

    echo "$result"
}

_strat_nvprof_extract_value () {
    local line="$1"
    local val=""
    if [[ "$line" == *":"* ]]; then
        val="${line##*:}"
    else
        read -ra _arr <<< "$line"
        local i
        for ((i=${#_arr[@]}-1; i>=0; i--)); do
            if [[ "${_arr[$i]}" =~ ^[0-9] ]]; then
                val="${_arr[$i]}"
                break
            fi
        done
    fi
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    val="${val%%%}"
    echo "$val"
}
