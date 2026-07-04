#!/bin/bash
## Name: stress-ng
## Description: Extract stress test results from stress-ng output
## Version: 1.0
## Priority: 12
## Sample: samples/stress-ng/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"stress-ng:"* ]]; then
        if [[ "$text" == *"bogo ops"* || "$text" == *"info:"* || "$text" == *"metrc"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local stressor_num=0

    # Extract stressor metrics from the summary table
    # "stress-ng: info:  [12345] stressor       bogo ops bogo ops/s  ..."
    # "stress-ng: info:  [12345] cpu              123456   12345.67  ..."

    local in_table=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect table header: "stressor" + "bogo ops"
        if [[ "$line" == *"stressor"* ]] && [[ "$line" == *"bogo ops"* ]]; then
            in_table=1
            continue
        fi

        # Duration line: "stress-ng: info:  [PID] successful run completed in 60.00s"
        if [[ "$line" == *"successful run completed"* ]]; then
            local _after="${line#*completed in }"
            read -ra _arr <<< "$_after"
            local duration="${_arr[0]}"
            [[ -n "$duration" ]] && result+="run_duration ${duration}"$'\n'
            continue
        fi

        # Parse stressor data rows
        if [[ $in_table -eq 1 ]]; then
            # Data line: "stress-ng: info:  [PID] <name>  <bogo_ops>  <bogo_ops_per_s_real>  <bogo_ops_per_s_usr>  <wall_clock>  <user>  <sys>"
            # Strip prefix: remove "stress-ng: info:  [PID] "
            local stripped="$line"
            if [[ "$stripped" == *"stress-ng:"* ]]; then
                stripped="${stripped#*]}"
                while [[ "$stripped" == " "* ]]; do stripped="${stripped# }"; done
            fi

            # Skip non-data lines (must start with lowercase letter)
            [[ "$stripped" =~ ^[a-z] ]] || continue

            read -ra _arr <<< "$stripped"
            local name="${_arr[0]}"
            local bogo_ops="${_arr[1]}"
            local bogo_ops_real="${_arr[2]}"
            local bogo_ops_usr="${_arr[3]}"
            local wall_clock="${_arr[4]}"
            local user_time="${_arr[5]}"
            local sys_time="${_arr[6]}"

            # Validate: bogo_ops should be numeric
            [[ "$bogo_ops" =~ ^[0-9] ]] || continue

            stressor_num=$((stressor_num + 1))
            local prefix=""
            if [[ $stressor_num -gt 1 ]]; then
                prefix="stressor${stressor_num}."
            fi

            result+="${prefix}name ${name}"$'\n'
            result+="${prefix}bogo_ops ${bogo_ops}"$'\n'
            [[ -n "$bogo_ops_real" ]] && result+="${prefix}bogo_ops_per_sec_real ${bogo_ops_real}"$'\n'
            [[ -n "$bogo_ops_usr" ]] && result+="${prefix}bogo_ops_per_sec_usr ${bogo_ops_usr}"$'\n'
            [[ -n "$wall_clock" ]] && result+="${prefix}wall_clock ${wall_clock}"$'\n'
            [[ -n "$user_time" ]] && result+="${prefix}user_time ${user_time}"$'\n'
            [[ -n "$sys_time" ]] && result+="${prefix}sys_time ${sys_time}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}
