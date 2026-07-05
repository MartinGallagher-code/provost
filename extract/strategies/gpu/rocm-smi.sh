#!/bin/bash
## Name: rocm-smi
## Description: Extract AMD GPU status from rocm-smi output
## Version: 1.0
## Priority: 10
## Sample: samples/rocm-smi/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    if [[ "$text" == *"rocm-smi"* ]] || [[ "$text" == *"ROCm"* ]]; then
        return 0
    fi
    if [[ "$text" == *"GPU["* ]] && [[ "$text" == *"SCLK"* ]]; then
        return 0
    fi
    if [[ "$text" == *"GPU["* ]] && [[ "$text" == *"MCLK"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local gpu_idx=0

    # rocm-smi outputs a table like:
    # ========================= ROCm System Management Interface =========================
    # ================================ Concise Info ======================================
    # GPU  Temp   AvgPwr  SCLK    MCLK     Fan     Perf  PwrCap  VRAM%   GPU%
    # 0    45.0c  35.0W   1500Mhz 945Mhz   0%      auto  300.0W  10%     25%
    # 1    42.0c  30.0W   1350Mhz 945Mhz   0%      auto  300.0W  8%      20%
    #
    # Also handles variations with edge temp columns

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip header/decoration lines
        [[ "$line" == "="* ]] && continue
        [[ "$line" == "-"* ]] && continue
        [[ "$line" =~ ^[[:space:]]*GPU[[:space:]] ]] && [[ "$line" != *"["* ]] && continue

        # Parse data lines: start with a GPU index number
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]] ]]; then
            local fields
            read -ra fields <<< "$line"

            # Need at least a few fields to be a valid data line
            [[ ${#fields[@]} -lt 4 ]] && continue

            # First field should be a small integer (GPU index)
            local idx="${fields[0]}"
            [[ ! "$idx" =~ ^[0-9]+$ ]] && continue

            gpu_idx=$((gpu_idx + 1))
            local prefix=""
            if [[ $gpu_idx -gt 1 ]]; then
                prefix="gpu${gpu_idx}."
            fi

            result+="${prefix}gpu_index ${idx}"$'\n'

            # Parse remaining fields by scanning for known patterns
            local i
            for (( i=1; i<${#fields[@]}; i++ )); do
                local f="${fields[$i]}"

                # Temperature: NN.Nc or NNc
                if [[ "$f" =~ ^([0-9]+\.?[0-9]*)c$ ]]; then
                    result+="${prefix}temp_edge_C ${BASH_REMATCH[1]}"$'\n'
                    continue
                fi

                # Power: NN.NW
                if [[ "$f" =~ ^([0-9]+\.?[0-9]*)W$ ]] && [[ "$f" != *"PwrCap"* ]]; then
                    # Distinguish AvgPwr from PwrCap by position (first W is AvgPwr)
                    if [[ -z "${_saw_power:-}" ]]; then
                        result+="${prefix}power_W ${BASH_REMATCH[1]}"$'\n'
                        _saw_power=1
                    fi
                    continue
                fi

                # SCLK: NNNNMhz or NNNNMHz
                if [[ "$f" =~ ^([0-9]+)[Mm][Hh]z$ ]]; then
                    if [[ -z "${_saw_sclk:-}" ]]; then
                        result+="${prefix}sclk_MHz ${BASH_REMATCH[1]}"$'\n'
                        _saw_sclk=1
                    else
                        result+="${prefix}mclk_MHz ${BASH_REMATCH[1]}"$'\n'
                    fi
                    continue
                fi

                # Fan/GPU/Memory utilization: NN%
                if [[ "$f" =~ ^([0-9]+)%$ ]]; then
                    if [[ -z "${_saw_fan:-}" ]]; then
                        result+="${prefix}fan_percent ${BASH_REMATCH[1]}"$'\n'
                        _saw_fan=1
                    elif [[ -z "${_saw_vram:-}" ]]; then
                        result+="${prefix}memory_use_percent ${BASH_REMATCH[1]}"$'\n'
                        _saw_vram=1
                    else
                        result+="${prefix}gpu_use_percent ${BASH_REMATCH[1]}"$'\n'
                    fi
                    continue
                fi
            done

            # Reset per-GPU tracking vars
            unset _saw_power _saw_sclk _saw_fan _saw_vram
        fi

    done <<< "$text"

    echo "$result"
}
