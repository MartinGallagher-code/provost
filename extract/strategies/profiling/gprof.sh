#!/bin/bash
## Name: gprof
## Description: Extract profiling data from GNU gprof flat profile and call graph output
## Version: 1.0
## Priority: 25
## Sample: samples/gprof/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong: gprof flat profile header
    if [[ "$text" == *"Flat profile:"* ]]; then
        return 0
    fi
    # gprof granularity line
    if [[ "$text" == *"granularity:"* ]] && [[ "$text" == *"each sample"* ]]; then
        return 0
    fi
    # gprof call graph header
    if [[ "$text" == *"Call graph"* ]] && [[ "$text" == *"index % time"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    # Column header pattern specific to gprof
    if [[ "$text" == *"% time"* ]] && [[ "$text" == *"cumulative"* ]] && \
       [[ "$text" == *"self"* ]] && [[ "$text" == *"calls"* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local in_flat=0
    local header_seen=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect flat profile section
        if [[ "$line" == *"Flat profile:"* ]]; then
            in_flat=1
            header_seen=0
            continue
        fi

        # Stop at call graph section (we focus on flat profile)
        if [[ "$line" == *"Call graph"* ]]; then
            in_flat=0
            continue
        fi

        # Skip granularity line
        if [[ "$line" == *"granularity:"* ]]; then
            continue
        fi

        # Detect column header
        if [[ $in_flat -eq 1 ]] && [[ "$line" == *"% time"* ]] && [[ "$line" == *"cumulative"* ]]; then
            header_seen=1
            continue
        fi

        # Skip blank/header continuation lines
        if [[ $in_flat -eq 1 ]] && [[ $header_seen -eq 0 ]]; then
            # Also check if this line is the column header
            if [[ "$line" == *"time"* ]] && [[ "$line" == *"seconds"* ]]; then
                header_seen=1
            fi
            continue
        fi

        # Parse flat profile data rows
        # Format: " %time  cumulative_secs  self_secs  calls  self_ms/call  total_ms/call  name"
        # Example: " 42.86      1.50          1.50   1000000     0.00         0.00  compute"
        if [[ $in_flat -eq 1 ]] && [[ $header_seen -eq 1 ]]; then
            read -ra _arr <<< "$line"
            [[ ${#_arr[@]} -lt 4 ]] && continue

            # First field should be a number (percent time)
            if [[ "${_arr[0]}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                n=$((n + 1))
                local pct_time="${_arr[0]}"
                local cum_secs="${_arr[1]}"
                local self_secs="${_arr[2]}"
                # Function name is the last field
                local fname="${_arr[${#_arr[@]}-1]}"
                # Calls field (index 3) may or may not be present
                local calls=""
                if [[ ${#_arr[@]} -ge 5 ]] && [[ "${_arr[3]}" =~ ^[0-9]+$ ]]; then
                    calls="${_arr[3]}"
                fi

                result+="func${n}_name ${fname}"$'\n'
                result+="func${n}_percent_time ${pct_time}"$'\n'
                result+="func${n}_cumulative_seconds ${cum_secs}"$'\n'
                result+="func${n}_self_seconds ${self_secs}"$'\n'
                [[ -n "$calls" ]] && result+="func${n}_calls ${calls}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
