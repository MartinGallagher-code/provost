#!/bin/bash
## Name: syslog
## Description: Extract fields from BSD/RFC 3164 syslog format log lines
## Version: 1.0
## Priority: 20
## Sample: samples/syslog/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Match BSD syslog timestamp pattern: Mon DD HH:MM:SS
    [[ "$text" =~ (^|$'\n')[A-Z][a-z]{2}\ [\ 0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\  ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local line_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Only process lines matching syslog format
        [[ "$line" =~ ^[A-Z][a-z]{2}\ [\ 0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\  ]] || continue

        line_num=$((line_num + 1))
        local prefix="line${line_num}"

        # Extract timestamp (first 15 chars: "Mon DD HH:MM:SS")
        local timestamp
        timestamp=$(_strat_syslog_get_timestamp "$line")
        result+="${prefix}.timestamp ${timestamp}"$'\n'

        # Extract hostname (word after timestamp)
        read -ra _arr <<< "$line"
        local hostname="${_arr[3]}"
        result+="${prefix}.hostname ${hostname}"$'\n'

        # Extract process and PID
        local process_part="${_arr[4]}"
        local process pid
        process="${process_part%%[*}"
        process="${process%:}"
        # Extract PID from brackets if present
        pid=""
        if [[ "$process_part" == *"["*"]"* ]]; then
            pid="${process_part#*[}"
            pid="${pid%%]*}"
        fi
        result+="${prefix}.process ${process}"$'\n'
        if [[ -n "$pid" ]]; then
            result+="${prefix}.pid ${pid}"$'\n'
        fi

        # Extract message (everything after process/pid field)
        local message
        message=$(_strat_syslog_get_message "$line")
        if [[ -n "$message" ]]; then
            result+="${prefix}.message ${message}"$'\n'
        fi

    done <<< "$text"

    echo "$result"
}

_strat_syslog_get_timestamp () {
    local line="$1"
    # Extract "Mon DD HH:MM:SS" and replace spaces/colons with underscores
    read -ra _arr <<< "$line"
    local ts="${_arr[0]}_${_arr[1]}_${_arr[2]}"
    # Replace colons with underscores in timestamp
    ts="${ts//:/_}"
    echo "$ts"
}

_strat_syslog_get_message () {
    local line="$1"
    # Message is everything after the 5th field's colon/bracket
    # Remove timestamp (3 fields), hostname (1 field), process[pid]: (1 field)
    read -ra _arr <<< "$line"
    # Reconstruct message from field 5 onwards
    local msg=""
    local i
    for ((i=5; i<${#_arr[@]}; i++)); do
        if [[ -z "$msg" ]]; then
            msg="${_arr[$i]}"
        else
            msg="${msg} ${_arr[$i]}"
        fi
    done
    # Also check if field 4 has trailing content after ":"
    local field4="${_arr[4]}"
    if [[ "$field4" == *":" ]]; then
        # Colon is at end, message starts at field 5 (already handled)
        :
    elif [[ "$field4" == *"]:" ]]; then
        # PID bracket + colon at end, message starts at field 5 (already handled)
        :
    fi
    echo "$msg"
}
