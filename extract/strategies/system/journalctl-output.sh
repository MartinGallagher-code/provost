#!/bin/bash
## Name: journalctl-output
## Description: Extract structured log entries from journalctl output
## Version: 1.0
## Priority: 22
## Technique: mixed
## Sample: samples/journalctl-output/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    _is_json "$text" && return 1
    # journalctl output has lines like: "Mar 31 10:30:00 hostname unit[pid]: message"
    # Check for month-day-time hostname pattern with bracketed PID
    local match_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Match pattern: Mon DD HH:MM:SS hostname something[digits]:
        case "$line" in
            [JFMASOND][aepuco][nbrylgptvc]\ [0-9]*\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\ *\[*\]:*)
                match_count=$((match_count + 1))
                ;;
        esac
        [[ $match_count -ge 3 ]] && return 0
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry_n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip lines starting with "--" (journalctl separators)
        [[ "$line" == "-- "*  ]] && continue

        # Parse: Month Day HH:MM:SS hostname unit[pid]: message
        # Split on spaces carefully
        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 5 ]] && continue

        local month="${_arr[0]}"
        local day="${_arr[1]}"
        local timestamp="${_arr[2]}"
        local hostname="${_arr[3]}"
        local unit_pid="${_arr[4]}"

        # Validate timestamp format
        case "$timestamp" in
            [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) ;;
            *) continue ;;
        esac

        entry_n=$((entry_n + 1))
        local prefix="entry${entry_n}"

        # Extract unit name and PID from "unit[pid]:" format
        local unit=""
        local pid=""
        if [[ "$unit_pid" == *"["*"]:"* ]]; then
            unit="${unit_pid%%\[*}"
            pid="${unit_pid#*\[}"
            pid="${pid%%\]*}"
        elif [[ "$unit_pid" == *":" ]]; then
            unit="${unit_pid%:}"
        else
            unit="$unit_pid"
        fi

        # Message is everything after the unit[pid]:
        local msg=""
        local i
        for ((i=5; i<${#_arr[@]}; i++)); do
            if [[ -z "$msg" ]]; then
                msg="${_arr[$i]}"
            else
                msg="${msg}_${_arr[$i]}"
            fi
        done

        result+="${prefix}.timestamp ${month}_${day}_${timestamp}"$'\n'
        result+="${prefix}.hostname ${hostname}"$'\n'
        [[ -n "$unit" ]] && result+="${prefix}.unit ${unit}"$'\n'
        [[ -n "$pid" ]] && result+="${prefix}.pid ${pid}"$'\n'
        [[ -n "$msg" ]] && result+="${prefix}.message ${msg}"$'\n'
    done <<< "$text"

    echo "$result"
}
