#!/bin/bash
## Name: gpu-burn
## Description: Extract GPU stress test results from gpu_burn output
## Version: 1.0
## Priority: 12
## Sample: samples/gpu-burn/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Must have "GPU" and "GF/s"
    if [[ "$text" != *"GPU"* ]]; then
        return 1
    fi
    if [[ "$text" != *"GF/s"* ]]; then
        return 1
    fi
    # Must have either "Burning for" or ("Tested" and "GPUs")
    if [[ "$text" == *"Burning for"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Tested"* ]] && \
       [[ "$text" == *"GPUs"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract burn duration: "Burning for 60 seconds."
    local burn_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Burning for"* ]]; then
            burn_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$burn_line" ]]; then
        local _after="${burn_line##*Burning for }"
        while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
        read -ra _arr <<< "$_after"
        local duration="${_arr[0]}"
        [[ -n "$duration" ]] && result+="burn_duration_seconds ${duration}"$'\n'
    fi

    # Extract GPU count: "Tested 2 GPUs:"
    local tested_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Tested"*"GPUs"* ]]; then
            tested_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$tested_line" ]]; then
        local _after="${tested_line##*Tested }"
        while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
        read -ra _arr <<< "$_after"
        local gpu_count="${_arr[0]}"
        [[ -n "$gpu_count" ]] && result+="gpu_count ${gpu_count}"$'\n'
    fi

    # Parse summary lines: "GPU 0: OK - Maximum ass temperature 68 C - Performance: 11239.5 GF/s"
    # These lines appear after "Tested N GPUs:" and are tab-indented
    local gpu_idx=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Match summary lines (tab-indented GPU results after "Tested")
        if _strat_gpu_burn_is_summary_line "$line"; then
            gpu_idx=$((gpu_idx + 1))
            local prefix=""
            if [[ $gpu_idx -gt 1 ]]; then
                prefix="gpu${gpu_idx}."
            fi

            # Extract GPU name from init lines: "GPU 0: Tesla V100-SXM2-32GB (UUID: ...)"
            local gpu_num
            gpu_num=$(_strat_gpu_burn_extract_gpu_num "$line")
            local gpu_name
            gpu_name=$(_strat_gpu_burn_find_gpu_name "$text" "$gpu_num")
            [[ -n "$gpu_name" ]] && result+="${prefix}gpu_name ${gpu_name}"$'\n'

            # Extract status (OK or FAULTY)
            local status
            status=$(_strat_gpu_burn_extract_status "$line")
            [[ -n "$status" ]] && result+="${prefix}status ${status}"$'\n'

            # Extract max temperature
            local max_temp
            max_temp=$(_strat_gpu_burn_extract_temp "$line")
            [[ -n "$max_temp" ]] && result+="${prefix}max_temp_C ${max_temp}"$'\n'

            # Extract performance
            local perf
            perf=$(_strat_gpu_burn_extract_perf "$line")
            [[ -n "$perf" ]] && result+="${prefix}performance_GF_per_s ${perf}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

_strat_gpu_burn_is_summary_line () {
    local line="$1"
    # Summary lines are tab-indented and contain "GPU" + status + temperature + performance
    if [[ "$line" =~ ^[[:space:]]+GPU\ [0-9]+: ]] && \
       [[ "$line" == *"GF/s"* ]]; then
        return 0
    fi
    return 1
}

_strat_gpu_burn_extract_gpu_num () {
    local line="$1"
    if [[ "$line" =~ GPU\ ([0-9]+): ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

_strat_gpu_burn_find_gpu_name () {
    local text="$1"
    local gpu_num="$2"
    # Look for "GPU N: ModelName (UUID: ...)" in the init section
    local _pattern="GPU ${gpu_num}: "
    while IFS= read -r _line; do
        if [[ "$_line" == "GPU ${gpu_num}: "* ]]; then
            # Extract model name between "GPU N: " and " (UUID:"
            local name="${_line#GPU ${gpu_num}: }"
            # Remove everything from " (UUID:" onward
            name="${name%% (UUID:*}"
            # Also handle case without UUID
            name="${name%% (*}"
            [[ -n "$name" ]] && echo "$name"
            return
        fi
    done <<< "$text"
}

_strat_gpu_burn_extract_status () {
    local line="$1"
    # "GPU 0: OK - ..." or "GPU 0: FAULTY - ..."
    if [[ "$line" =~ GPU\ [0-9]+:[[:space:]]*([A-Z]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

_strat_gpu_burn_extract_temp () {
    local line="$1"
    # "Maximum ass temperature 68 C" or "Maximumass temperature 68 C"
    if [[ "$line" =~ temperature[[:space:]]+([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

_strat_gpu_burn_extract_perf () {
    local line="$1"
    # "Performance: 11239.5 GF/s"
    if [[ "$line" =~ Performance:[[:space:]]*([0-9.]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}
