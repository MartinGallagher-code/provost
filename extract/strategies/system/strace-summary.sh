#!/bin/bash
## Name: strace-summary
## Description: Extract syscall statistics from strace -c summary output
## Version: 1.0
## Priority: 30
## Sample: samples/strace-summary/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    # Reject JSON
    _is_json "$1" && return 1
    # Look for "% time" and "syscall" on the same line, or
    # a dashed separator line followed by syscall data pattern
    local found_header=0
    local found_dashes=0
    while IFS= read -r line; do
        if [[ "$line" == *"% time"* ]] && [[ "$line" == *"syscall"* ]]; then
            found_header=1
        fi
        if [[ "$line" == ------* ]] && [[ "$line" == *------ ]]; then
            found_dashes=1
        fi
    done <<< "$text"
    if [[ $found_header -eq 1 ]]; then
        return 0
    fi
    # Also detect if we see dashed lines and a "total" line
    if [[ $found_dashes -eq 1 ]] && [[ "$text" == *"total"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    # State: 0=before data, 1=in data rows, 2=after closing dashes (total line area)
    local state=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip header line
        if [[ "$line" == *"% time"* ]] && [[ "$line" == *"syscall"* ]]; then
            state=0
            continue
        fi

        # Dash separator transitions state
        if [[ "$line" == ------* ]]; then
            if [[ $state -eq 0 ]]; then
                state=1
            elif [[ $state -eq 1 ]]; then
                state=2
            fi
            continue
        fi

        # Only process lines in data (1) or total (2) states
        [[ $state -eq 0 ]] && continue

        # Parse data row: "  42.86    0.003000          12       250           read"
        # or with errors: " 14.29    0.001000          10       100        10 open"
        # or total line:  "100.00    0.007000                   950        10 total"
        read -ra _arr <<< "$line"
        # Need at least 3 fields
        [[ ${#_arr[@]} -lt 3 ]] && continue

        # Last field is the syscall name
        local syscall_name="${_arr[${#_arr[@]}-1]}"

        # First field is time percentage
        local time_pct="${_arr[0]}"

        # Second field is seconds
        local seconds="${_arr[1]}"

        if [[ "$syscall_name" == "total" ]]; then
            # Total line: extract total_calls, total_errors, total_seconds
            result+="total_time_pct ${time_pct}"$'\n'
            result+="total_seconds ${seconds}"$'\n'
            # Parse calls and errors from the total line
            # Format varies: "100.00    0.007000                   950        10 total"
            # The calls field is second-to-last number, errors is between calls and syscall
            # With array indexing: fields might be sparse
            # Total line has: time_pct seconds [usecs/call] calls [errors] total
            local total_calls=""
            local total_errors=""
            local idx=${#_arr[@]}
            idx=$((idx - 2))  # second-to-last is either errors or calls
            if [[ $idx -ge 2 ]]; then
                # Check if there are errors by field count
                # If arr has 6 fields: time_pct seconds usecs calls errors total
                # If arr has 5 fields: time_pct seconds usecs calls total  (or time_pct seconds calls errors total)
                # If arr has 4 fields: time_pct seconds calls total
                case ${#_arr[@]} in
                    6) total_calls="${_arr[3]}"; total_errors="${_arr[4]}" ;;
                    5)
                        # Could be: pct secs usecs calls total  OR  pct secs calls errors total
                        # Total line often omits usecs/call, so 5 fields = pct secs calls errors total
                        total_calls="${_arr[2]}"; total_errors="${_arr[3]}"
                        ;;
                    4) total_calls="${_arr[2]}"; total_errors="" ;;
                    *) total_calls="${_arr[$idx]}" ;;
                esac
            fi
            [[ -n "$total_calls" ]] && result+="total_calls ${total_calls}"$'\n'
            [[ -n "$total_errors" ]] && result+="total_errors ${total_errors}"$'\n'
        else
            # Regular syscall row
            n=$((n + 1))
            result+="syscall${n}_name ${syscall_name}"$'\n'
            result+="syscall${n}_time_pct ${time_pct}"$'\n'
            result+="syscall${n}_seconds ${seconds}"$'\n'

            # Parse calls and errors
            # Row formats:
            # 6 fields: time_pct seconds usecs_per_call calls errors syscall
            # 5 fields: time_pct seconds usecs_per_call calls syscall (no errors)
            local calls="" errors=""
            case ${#_arr[@]} in
                6) calls="${_arr[3]}"; errors="${_arr[4]}" ;;
                5) calls="${_arr[3]}"; errors="" ;;
                4) calls="${_arr[2]}"; errors="" ;;
            esac
            [[ -n "$calls" ]] && result+="syscall${n}_calls ${calls}"$'\n'
            [[ -n "$errors" ]] && result+="syscall${n}_errors ${errors}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
