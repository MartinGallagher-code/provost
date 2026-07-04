#!/bin/bash
## Name: uptime
## Description: Extract uptime duration, user count, and load averages from uptime command output
## Version: 1.0
## Priority: 35
## Sample: samples/uptime/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Reject JSON
    _is_json "$1" && return 1
    # Must contain "load average:" and "up"
    [[ "$text" == *"load average:"* ]] || return 1
    [[ "$text" == *" up "* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""

    # uptime output is typically a single line:
    #  " 15:27:38 up 14 min,  0 user,  load average: 0.22, 0.62, 0.82"
    #  " 09:15:03 up 42 days,  5:23,  3 users,  load average: 1.25, 0.98, 0.76"
    #  " 09:15:03 up 2 days, 12:30,  1 user,  load average: 0.50, 0.40, 0.30"

    local line=""
    while IFS= read -r _l; do
        [[ -z "$_l" ]] && continue
        if [[ "$_l" == *"load average:"* ]]; then
            line="$_l"
            break
        fi
    done <<< "$text"
    [[ -z "$line" ]] && return 0

    # Extract load averages
    if [[ "$line" =~ load[[:space:]]+average:[[:space:]]*([0-9.]+)[,[:space:]]+([0-9.]+)[,[:space:]]+([0-9.]+) ]]; then
        result+="load_avg_1min ${BASH_REMATCH[1]}"$'\n'
        result+="load_avg_5min ${BASH_REMATCH[2]}"$'\n'
        result+="load_avg_15min ${BASH_REMATCH[3]}"$'\n'
    fi

    # Extract user count
    if [[ "$line" =~ ([0-9]+)[[:space:]]+users? ]]; then
        result+="users ${BASH_REMATCH[1]}"$'\n'
    fi

    # Extract uptime days (if present)
    if [[ "$line" =~ up[[:space:]]+([0-9]+)[[:space:]]+days? ]]; then
        result+="uptime_days ${BASH_REMATCH[1]}"$'\n'
    fi

    # Extract uptime minutes (if "N min" format, no days)
    if [[ "$line" =~ up[[:space:]]+([0-9]+)[[:space:]]+min ]]; then
        result+="uptime_minutes ${BASH_REMATCH[1]}"$'\n'
    fi

    [[ -n "$result" ]] && echo "${result%$'\n'}"
}
