#!/bin/bash
## Name: ltrace-summary
## Description: Extract library call statistics from ltrace summary output
## Version: 1.0
## Priority: 25
## Sample: samples/ltrace-summary/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Must distinguish from strace-summary which has similar format
    # ltrace outputs library function names (e.g., malloc, strlen, printf)
    # while strace outputs syscall names (e.g., read, write, open)

    # Strong: ltrace mentioned
    if [[ "$text" == *"ltrace"* ]]; then
        if [[ "$text" == *"% time"* ]] || [[ "$text" == *"calls"* ]] || \
           [[ "$text" == *"function"* ]]; then
            return 0
        fi
    fi

    # Detect ltrace summary table with library function indicators
    local has_header=0
    local has_libfunc=0
    while IFS= read -r line; do
        if [[ "$line" == *"% time"* ]] && [[ "$line" == *"calls"* ]] && [[ "$line" == *"function"* ]]; then
            has_header=1
        fi
        # Library function indicators (common libc functions)
        if [[ "$line" == *"malloc"* ]] || [[ "$line" == *"free"* ]] || \
           [[ "$line" == *"strlen"* ]] || [[ "$line" == *"printf"* ]] || \
           [[ "$line" == *"strcmp"* ]] || [[ "$line" == *"memcpy"* ]] || \
           [[ "$line" == *"fopen"* ]] || [[ "$line" == *"fclose"* ]] || \
           [[ "$line" == *"__libc"* ]]; then
            has_libfunc=1
        fi
    done <<< "$text"

    # Need both header and library function names to distinguish from strace
    if [[ $has_header -eq 1 ]] && [[ $has_libfunc -eq 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local in_data=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect header line
        if [[ "$line" == *"% time"* ]] && [[ "$line" == *"calls"* ]] && [[ "$line" == *"function"* ]]; then
            in_data=0
            continue
        fi

        # Dash separator starts data
        if [[ "$line" == ------* ]]; then
            if [[ $in_data -eq 0 ]]; then
                in_data=1
            elif [[ $in_data -eq 1 ]]; then
                # Second dashes = total line follows
                in_data=2
            fi
            continue
        fi

        # Parse data rows
        # Format: "  42.86    0.003000          250  malloc"
        # or:     "  42.86    0.003000          250        10  malloc"  (with errors)
        if [[ $in_data -ge 1 ]]; then
            read -ra _arr <<< "$line"
            [[ ${#_arr[@]} -lt 3 ]] && continue

            # Last field is function name
            local func_name="${_arr[${#_arr[@]}-1]}"
            # First field is time percentage
            local time_pct="${_arr[0]}"
            # Second field is seconds
            local seconds="${_arr[1]}"

            if [[ "$func_name" == "total" ]]; then
                result+="total_time_pct ${time_pct}"$'\n'
                result+="total_seconds ${seconds}"$'\n'
                # Parse total calls
                if [[ ${#_arr[@]} -ge 4 ]]; then
                    local total_calls="${_arr[2]}"
                    result+="total_calls ${total_calls}"$'\n'
                fi
            else
                n=$((n + 1))
                result+="func${n}_name ${func_name}"$'\n'
                result+="func${n}_percent_time ${time_pct}"$'\n'
                result+="func${n}_seconds ${seconds}"$'\n'

                # Parse calls (third numeric field)
                if [[ ${#_arr[@]} -ge 4 ]]; then
                    local calls="${_arr[2]}"
                    # Handle usecs/call field if present
                    if [[ ${#_arr[@]} -ge 5 ]]; then
                        calls="${_arr[2]}"
                    fi
                    result+="func${n}_calls ${calls}"$'\n'
                fi
            fi
        fi
    done <<< "$text"

    echo "$result"
}
