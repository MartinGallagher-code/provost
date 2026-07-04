#!/bin/bash
## Name: time-output
## Description: Extract timing fields from /usr/bin/time output (real/user/sys)
## Version: 1.0
## Priority: 25
## Sample: samples/time-output/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Detect basic time output: "real    0m1.234s" pattern
    # Or verbose time output: "Elapsed" or "Maximum resident set size"
    if [[ "$text" =~ (^|$'\n')real\ *[0-9] ]]; then
        return 0
    fi
    if [[ "$text" == *"Elapsed"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Handle basic format: real/user/sys lines
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" == "real "* || "$line" == "real	"* ]]; then
            local val
            val=$(_strat_time_output_parse_field "$line" "real")
            [[ -n "$val" ]] && result+="real ${val}"$'\n'
        elif [[ "$line" == "user "* || "$line" == "user	"* ]]; then
            local val
            val=$(_strat_time_output_parse_field "$line" "user")
            [[ -n "$val" ]] && result+="user ${val}"$'\n'
        elif [[ "$line" == "sys "* || "$line" == "sys	"* ]]; then
            local val
            val=$(_strat_time_output_parse_field "$line" "sys")
            [[ -n "$val" ]] && result+="sys ${val}"$'\n'
        fi
    done <<< "$text"

    # Handle verbose format: "key: value" lines from GNU time -v
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" == *"Maximum resident set size"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            val="${val// /_}"
            val="${val#_}"
            val="${val%_}"
            [[ -n "$val" ]] && result+="Maximum_resident_set_size ${val}"$'\n'
        elif [[ "$line" == *"Elapsed"*"wall"*"clock"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            val="${val// /_}"
            val="${val#_}"
            val="${val%_}"
            [[ -n "$val" ]] && result+="Elapsed_wall_clock_time ${val}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

_strat_time_output_parse_field () {
    local line="$1"
    local field="$2"
    # Extract the time value after the field name
    # Input: "real    0m1.234s" -> "0m1.234s"
    local val="${line#${field}}"
    while [[ "$val" == " "* || "$val" == "	"* ]]; do val="${val#?}"; done
    echo "$val"
}
