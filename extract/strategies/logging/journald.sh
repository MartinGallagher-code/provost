#!/bin/bash
## Name: journald
## Description: Extract fields from systemd journal output format
## Version: 1.0
## Priority: 14
## Sample: samples/journald/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Detect syslog-timestamp lines containing systemd-style unit names
    # (systemd[, .service, .target, .socket, etc.) or common systemd units
    if [[ "$text" =~ ^[A-Z][a-z]{2}" "[\ 0-9][0-9]" "[0-9]{2}:[0-9]{2}:[0-9]{2}" " ]]; then
        # Must contain systemd markers to distinguish from plain syslog
        if [[ "$text" == *"systemd["* ]]; then
            return 0
        fi
        if [[ "$text" == *".service"* || "$text" == *".target"* || "$text" == *".socket"* || "$text" == *".timer"* || "$text" == *".mount"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local line_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Only process lines matching syslog timestamp format
        if ! [[ "$line" =~ ^[A-Z][a-z]{2}" "[\ 0-9][0-9]" "[0-9]{2}:[0-9]{2}:[0-9]{2}" " ]]; then
            continue
        fi

        line_num=$((line_num + 1))
        local prefix="line${line_num}"

        # Extract timestamp (first 3 fields: "Mon DD HH:MM:SS")
        local timestamp
        timestamp=$(_strat_journald_get_timestamp "$line")
        result+="${prefix}.timestamp ${timestamp}"$'\n'

        # Extract hostname (4th field) and unit name (5th field)
        read -ra _arr <<< "$line"
        local hostname="${_arr[3]}"
        result+="${prefix}.hostname ${hostname}"$'\n'

        # Extract unit name (5th field, before [ or :)
        local unit_part="${_arr[4]}"
        local unit="${unit_part%%\[*}"
        unit="${unit%%:*}"
        result+="${prefix}.unit ${unit}"$'\n'

        # Extract PID if present (inside brackets)
        if [[ "$unit_part" =~ \[([0-9]+)\] ]]; then
            result+="${prefix}.pid ${BASH_REMATCH[1]}"$'\n'
        fi

        # Extract message (everything after the unit/pid field)
        local message
        message=$(_strat_journald_get_message "$line")
        if [[ -n "$message" ]]; then
            result+="${prefix}.message ${message}"$'\n'
        fi

    done <<< "$text"

    echo "$result"
}

_strat_journald_get_timestamp () {
    local line="$1"
    read -ra _arr <<< "$line"
    local ts="${_arr[0]}_${_arr[1]}_${_arr[2]}"
    ts="${ts//:/_}"
    echo "$ts"
}

_strat_journald_get_message () {
    local line="$1"
    # Remove the first 5 fields (month day time hostname unit[pid]:)
    read -ra _arr <<< "$line"
    # Rebuild from field 5 onwards (skip 0-4)
    local msg=""
    local i
    for ((i=5; i<${#_arr[@]}; i++)); do
        if [[ -n "$msg" ]]; then
            msg+="_"
        fi
        msg+="${_arr[$i]}"
    done
    # Strip leading colon, brackets, underscores
    while [[ "$msg" == ":"* || "$msg" == "]"* || "$msg" == "["* ]]; do msg="${msg#?}"; done
    while [[ "$msg" == "_"* ]]; do msg="${msg#_}"; done
    echo "$msg"
}
