#!/bin/bash
## Name: tau
## Description: Extract profiling data from TAU pprof format output
## Version: 1.0
## Priority: 25
## Sample: samples/tau/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong: TAU-specific header
    if [[ "$text" == *"TAU"* ]] && [[ "$text" == *"Exclusive"* || "$text" == *"Inclusive"* ]]; then
        return 0
    fi
    # pprof tabular format: NODE/CONTEXT/THREAD header pattern
    if [[ "$text" == *"NODE"* ]] && [[ "$text" == *"CONTEXT"* ]] && [[ "$text" == *"THREAD"* ]]; then
        if [[ "$text" == *"Exclusive"* ]] || [[ "$text" == *"Inclusive"* ]]; then
            return 0
        fi
    fi
    # Detect pprof column header
    if [[ "$text" == *"Calls"* ]] && [[ "$text" == *"Excl"* ]] && [[ "$text" == *"Incl"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local in_data=0
    local header_found=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect column header line (Calls, Excl, Incl, etc.)
        if [[ "$line" == *"Calls"* ]] && [[ "$line" == *"Excl"* ]] && [[ "$line" == *"Incl"* ]]; then
            header_found=1
            in_data=0
            continue
        fi

        # Dash separators after header start data section
        if [[ $header_found -eq 1 ]] && [[ "$line" == ------* || "$line" == "==="* ]]; then
            in_data=1
            continue
        fi

        # Parse NODE/CONTEXT/THREAD lines if present
        if [[ "$line" == *"NODE"* ]] && [[ "$line" == *"CONTEXT"* ]] && [[ "$line" == *"THREAD"* ]]; then
            # Extract node/context/thread identifiers if numeric
            continue
        fi

        # Parse data rows in pprof format
        # Typical: "  1000   12.345   45.678   100.0    0.123  function_name"
        # or:      "  1000   12.345   45.678    27.0   function_name"
        if [[ $in_data -eq 1 ]] || [[ $header_found -eq 1 ]]; then
            # Skip non-data lines
            [[ "$line" == ------* ]] && continue
            [[ "$line" == "==="* ]] && continue

            read -ra _arr <<< "$line"
            # Need at least 4 fields: calls excl incl function_name
            [[ ${#_arr[@]} -lt 4 ]] && continue

            # First field should be numeric (calls)
            if [[ "${_arr[0]}" =~ ^[0-9] ]]; then
                n=$((n + 1))
                local calls="${_arr[0]}"
                local excl="${_arr[1]}"
                local incl="${_arr[2]}"
                # Function name is the last field (may contain spaces)
                local fname="${_arr[${#_arr[@]}-1]}"
                # Check if there's a percentage field
                local pct=""
                if [[ ${#_arr[@]} -ge 5 ]]; then
                    # Percentage might be field 3
                    if [[ "${_arr[3]}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                        pct="${_arr[3]}"
                    fi
                fi

                result+="func${n}_name ${fname}"$'\n'
                result+="func${n}_calls ${calls}"$'\n'
                result+="func${n}_exclusive_time ${excl}"$'\n'
                result+="func${n}_inclusive_time ${incl}"$'\n'
                [[ -n "$pct" ]] && result+="func${n}_percent ${pct}"$'\n'
                in_data=1
            fi
        fi
    done <<< "$text"

    echo "$result"
}
