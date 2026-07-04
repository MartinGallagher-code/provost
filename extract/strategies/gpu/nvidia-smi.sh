#!/bin/bash
## Name: nvidia-smi
## Description: Extract GPU status from nvidia-smi output
## Version: 1.0
## Priority: 10
## Sample: samples/nvidia-smi/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    if [[ "$text" == *"NVIDIA-SMI"* ]] || [[ "$text" == *"nvidia-smi"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Driver Version"* ]] && [[ "$text" == *"CUDA Version"* ]]; then
        return 0
    fi
    if [[ "$text" == *"GPU Name"* ]] && [[ "$text" == *"GPU Current Temp"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Detect format: -q verbose vs table
    if [[ "$text" == *"GPU Current Temp"* ]] || [[ "$text" == *"FB Memory Usage"* ]]; then
        result+=$(_strat_nvidia_smi_extract_query "$text")
    else
        result+=$(_strat_nvidia_smi_extract_table "$text")
    fi

    # Extract driver version from header: "NVIDIA-SMI 535.129.03   Driver Version: 535.129.03   CUDA Version: 12.2"
    local driver_ver=""
    driver_ver=$(_strat_nvidia_smi_extract_header_field "$text" "Driver Version")
    [[ -n "$driver_ver" ]] && result+="driver_version ${driver_ver}"$'\n'

    local cuda_ver=""
    cuda_ver=$(_strat_nvidia_smi_extract_header_field "$text" "CUDA Version")
    [[ -n "$cuda_ver" ]] && result+="cuda_version ${cuda_ver}"$'\n'

    echo "$result"
}

_strat_nvidia_smi_extract_header_field () {
    local text="$1"
    local field="$2"
    while IFS= read -r line; do
        if [[ "$line" == *"${field}"* ]]; then
            # "Driver Version: 535.129.03" or "CUDA Version: 12.2"
            local after="${line##*${field}:}"
            # Trim leading spaces
            while [[ "$after" == " "* ]]; do after="${after# }"; done
            # Take first token
            read -ra _arr <<< "$after"
            echo "${_arr[0]}"
            return
        fi
    done <<< "$text"
}

_strat_nvidia_smi_extract_table () {
    local text="$1"
    local result=""
    local gpu_idx=0

    # Table format parsing. Lines look like:
    # |   0  Tesla V100-SXM2  On   | 00000000:00:1E.0 Off |                    0 |
    # |  45C    P0    35W / 300W |      0MiB / 32768MiB |      0%      Default |
    # We parse pairs of lines: the GPU name line and the stats line

    local name_line=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # GPU name line: starts with |, has a number at beginning, GPU name
        if [[ "$line" =~ ^\|[[:space:]]*([0-9]+)[[:space:]]+([A-Za-z0-9 _./-]+) ]]; then
            local maybe_idx="${BASH_REMATCH[1]}"
            local maybe_name="${BASH_REMATCH[2]}"
            # Trim trailing spaces from name
            maybe_name="${maybe_name%"${maybe_name##*[![:space:]]}"}"
            # Verify this is a GPU name line (not stats)
            if [[ "$maybe_name" != *"MiB"* ]] && [[ "$maybe_name" != *"%"* ]] && [[ "$maybe_name" != *"W /"* ]]; then
                name_line="$line"
                gpu_idx=$((gpu_idx + 1))
                local prefix=""
                if [[ $gpu_idx -gt 1 ]]; then
                    prefix="gpu${gpu_idx}."
                fi
                result+="${prefix}gpu_index ${maybe_idx}"$'\n'
                result+="${prefix}name ${maybe_name}"$'\n'
            fi
            continue
        fi

        # Stats line: contains temp, power, memory, utilization
        # |  45C    P0    35W / 300W |      0MiB / 32768MiB |      0%      Default |
        if [[ "$line" == *"MiB"* ]] && [[ "$line" == *"C "* ]] && [[ "$line" == *"W "* ]]; then
            local prefix=""
            if [[ $gpu_idx -gt 1 ]]; then
                prefix="gpu${gpu_idx}."
            fi

            # Temperature: NNC
            if [[ "$line" =~ ([0-9]+)C ]]; then
                result+="${prefix}temp_C ${BASH_REMATCH[1]}"$'\n'
            fi

            # Power: NNW / NNNW
            if [[ "$line" =~ ([0-9]+)W[[:space:]]*/[[:space:]]*([0-9]+)W ]]; then
                result+="${prefix}power_draw_W ${BASH_REMATCH[1]}"$'\n'
                result+="${prefix}power_cap_W ${BASH_REMATCH[2]}"$'\n'
            fi

            # Memory: NNNMiB / NNNMiB
            if [[ "$line" =~ ([0-9]+)MiB[[:space:]]*/[[:space:]]*([0-9]+)MiB ]]; then
                result+="${prefix}memory_used_MiB ${BASH_REMATCH[1]}"$'\n'
                result+="${prefix}memory_total_MiB ${BASH_REMATCH[2]}"$'\n'
            fi

            continue
        fi

        # Utilization line (sometimes separate): "| N%   Default |"
        if [[ "$line" =~ ^\| ]] && [[ "$line" =~ ([0-9]+)% ]] && [[ "$line" != *"MiB"* ]] && [[ "$line" != *"W "* ]]; then
            local prefix=""
            if [[ $gpu_idx -gt 1 ]]; then
                prefix="gpu${gpu_idx}."
            fi
            result+="${prefix}gpu_util_percent ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

    done <<< "$text"

    echo -n "$result"
}

_strat_nvidia_smi_extract_query () {
    local text="$1"
    local result=""
    local gpu_idx=0
    local prefix=""
    local in_fb_memory=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # GPU section: "GPU 00000000:00:1E.0"
        if [[ "$line" =~ ^GPU\ [0-9A-Fa-f] ]]; then
            gpu_idx=$((gpu_idx + 1))
            prefix=""
            if [[ $gpu_idx -gt 1 ]]; then
                prefix="gpu${gpu_idx}."
            fi
            in_fb_memory=0
            continue
        fi

        # Product Name
        if [[ "$line" =~ ^[[:space:]]*Product\ Name[[:space:]]*:[[:space:]]*(.+) ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val%"${val##*[![:space:]]}"}"
            result+="${prefix}name ${val}"$'\n'
            continue
        fi

        # GPU Current Temp
        if [[ "$line" =~ ^[[:space:]]*GPU\ Current\ Temp[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            result+="${prefix}temp_C ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Power Draw
        if [[ "$line" =~ ^[[:space:]]*Power\ Draw[[:space:]]*:[[:space:]]*([0-9.]+) ]]; then
            result+="${prefix}power_draw_W ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Power Limit
        if [[ "$line" =~ ^[[:space:]]*Power\ Limit[[:space:]]*:[[:space:]]*([0-9.]+) ]]; then
            result+="${prefix}power_cap_W ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # FB Memory Usage section
        if [[ "$line" =~ ^[[:space:]]*FB\ Memory\ Usage ]]; then
            in_fb_memory=1
            continue
        fi

        if [[ $in_fb_memory -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*Total[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                result+="${prefix}memory_total_MiB ${BASH_REMATCH[1]}"$'\n'
                continue
            fi
            if [[ "$line" =~ ^[[:space:]]*Used[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                result+="${prefix}memory_used_MiB ${BASH_REMATCH[1]}"$'\n'
                in_fb_memory=0
                continue
            fi
        fi

        # Gpu utilization
        if [[ "$line" =~ ^[[:space:]]*Gpu[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*% ]]; then
            result+="${prefix}gpu_util_percent ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Memory utilization
        if [[ "$line" =~ ^[[:space:]]*Memory[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*% ]]; then
            result+="${prefix}mem_util_percent ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

    done <<< "$text"

    echo -n "$result"
}
