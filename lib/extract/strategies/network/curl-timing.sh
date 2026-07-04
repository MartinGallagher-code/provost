#!/bin/bash
## Name: curl-timing
## Description: Extract timing metrics from curl -w format output
## Version: 1.0
## Priority: 22
## Technique: kv_colon
## Sample: samples/curl-timing/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
    _is_json "$text" && return 1
    # curl -w output contains timing fields like time_namelookup, time_connect, etc.
    local timing_count=0
    while IFS= read -r line; do
        case "$line" in
            *"time_namelookup"*|*"time_connect"*|*"time_total"*|*"time_starttransfer"*)
                timing_count=$((timing_count + 1))
                ;;
        esac
    done <<< "$text"
    if [[ $timing_count -ge 2 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Handle key: value format
        if [[ "$line" == *": "* ]]; then
            local key="${line%%:*}"
            local val="${line#*: }"
            # Trim whitespace
            while [[ "$key" == " "* ]]; do key="${key# }"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            # Replace spaces with underscores
            key="${key// /_}"
            val="${val// /_}"
            [[ -n "$key" && -n "$val" ]] && result+="${key} ${val}"$'\n'
            continue
        fi

        # Handle key=value format (curl -w with custom format)
        if [[ "$line" == *"="* && "$line" != *"=="* ]]; then
            local key="${line%%=*}"
            local val="${line#*=}"
            while [[ "$key" == " "* ]]; do key="${key# }"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            key="${key// /_}"
            val="${val// /_}"
            [[ -n "$key" && -n "$val" ]] && result+="${key} ${val}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
