#!/bin/bash
## Name: uprof
## Description: Extract performance metrics from AMD uProf output
## Version: 1.0
## Priority: 25
## Sample: samples/uprof/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong indicator: uProf in output
    if [[ "$text" == *"uProf"* ]] || [[ "$text" == *"AMD uProf"* ]]; then
        return 0
    fi
    # Alternative: AMD-specific metrics together
    local metric_count=0
    if [[ "$text" == *"IPC"* ]]; then metric_count=$((metric_count + 1)); fi
    if [[ "$text" == *"Retired Instructions"* ]]; then metric_count=$((metric_count + 1)); fi
    if [[ "$text" == *"AMD"* ]]; then metric_count=$((metric_count + 1)); fi
    if [[ "$text" == *"L1 Data Cache"* ]] || [[ "$text" == *"L2 Cache"* ]]; then metric_count=$((metric_count + 1)); fi
    if [[ "$text" == *"Branch Misprediction"* ]] || [[ "$text" == *"Branch Miss"* ]]; then metric_count=$((metric_count + 1)); fi
    # Need AMD + at least 2 other uProf-specific metrics
    [[ $metric_count -ge 3 ]]
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # IPC
        if [[ "$line" == *"IPC"* ]] && [[ "$line" =~ [0-9] ]]; then
            local val
            val=$(_strat_uprof_extract_value "$line")
            [[ -n "$val" ]] && result+="ipc ${val}"$'\n'
            continue
        fi

        # Retired Instructions
        if [[ "$line" == *"Retired Instructions"* ]] || [[ "$line" == *"retired_instructions"* ]]; then
            local val
            val=$(_strat_uprof_extract_value "$line")
            [[ -n "$val" ]] && result+="retired_instructions ${val}"$'\n'
            continue
        fi

        # Cache miss rate
        if [[ "$line" == *"Cache Miss"* ]] || [[ "$line" == *"cache miss rate"* ]] || \
           [[ "$line" == *"Cache miss ratio"* ]]; then
            local val
            val=$(_strat_uprof_extract_value "$line")
            [[ -n "$val" ]] && result+="cache_miss_rate ${val}"$'\n'
            continue
        fi

        # Branch miss rate
        if [[ "$line" == *"Branch Misprediction"* ]] || [[ "$line" == *"Branch Miss"* ]] || \
           [[ "$line" == *"branch miss"* ]]; then
            local val
            val=$(_strat_uprof_extract_value "$line")
            [[ -n "$val" ]] && result+="branch_miss_rate ${val}"$'\n'
            continue
        fi

        # Elapsed time
        if [[ "$line" == *"Elapsed"* ]] || [[ "$line" == *"elapsed"* ]] || \
           [[ "$line" == *"Duration"* ]]; then
            if [[ "$line" =~ [0-9] ]]; then
                local val
                val=$(_strat_uprof_extract_value "$line")
                [[ -n "$val" ]] && result+="elapsed_time ${val}"$'\n'
            fi
            continue
        fi

        # L1/L2/L3 cache hit rates if present
        if [[ "$line" == *"L1"*"Hit"* ]]; then
            local val
            val=$(_strat_uprof_extract_value "$line")
            [[ -n "$val" ]] && result+="l1_hit_rate ${val}"$'\n'
            continue
        fi
        if [[ "$line" == *"L2"*"Hit"* ]]; then
            local val
            val=$(_strat_uprof_extract_value "$line")
            [[ -n "$val" ]] && result+="l2_hit_rate ${val}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}

_strat_uprof_extract_value () {
    local line="$1"
    local val=""
    # Try "Key: value" format first
    if [[ "$line" == *":"* ]]; then
        val="${line##*:}"
    elif [[ "$line" == *"="* ]]; then
        val="${line##*=}"
    else
        # Take last numeric token
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
    # Remove common suffixes
    val="${val%%%}"
    val="${val%s}"
    # Remove commas from large numbers
    val="${val//,/}"
    echo "$val"
}
