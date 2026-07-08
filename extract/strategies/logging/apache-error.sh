#!/bin/bash
## Name: apache-error
## Description: Extract fields from Apache/nginx error log format
## Version: 1.0
## Priority: 12
## Sample: samples/apache-error/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Match lines starting with [DayOfWeek Month (e.g., [Wed Jan, [Mon Feb)
    # Use variable for regex: (^|newline) to match any line start
    local _nl=$'\n'
    local _re="(^|${_nl})\[[A-Z][a-z]{2} [A-Z][a-z]"
    [[ "$text" =~ $_re ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local line_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Only process lines matching error log format
        if ! [[ "$line" =~ ^\[[A-Z][a-z]{2}\ [A-Z][a-z] ]]; then
            continue
        fi

        line_num=$((line_num + 1))
        local prefix="line${line_num}"

        # Extract timestamp: everything in the first brackets
        local timestamp=""
        if [[ "$line" =~ ^\[([^\]]*)\] ]]; then
            timestamp="${BASH_REMATCH[1]}"
        fi
        result+="${prefix}.timestamp ${timestamp}"$'\n'

        # Extract severity: [error], [warn], [notice], etc.
        # It's in the second bracket group
        local severity=""
        local _after_first="${line#*] }"
        if [[ "$_after_first" =~ ^\[([a-z]*)\] ]]; then
            severity="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$severity" ]]; then
            result+="${prefix}.severity ${severity}"$'\n'
        fi

        # Extract client IP if present: [client IP:port]
        local client=""
        if [[ "$line" =~ \[client\ ([0-9.]*) ]]; then
            client="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$client" ]]; then
            result+="${prefix}.client ${client}"$'\n'
        fi

        # Extract message: everything after the last bracket group
        local message="$line"
        # Remove all bracket groups from the front
        while [[ "$message" =~ ^\[([^\]]*)\](\ *) ]]; do
            message="${message#*]}"
            # Strip leading space
            while [[ "$message" == " "* ]]; do message="${message# }"; done
        done
        if [[ -n "$message" ]]; then
            result+="${prefix}.message ${message}"$'\n'
        fi

    done <<< "$text"

    echo "$result"
}
