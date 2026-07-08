#!/bin/bash
## Name: http-headers
## Description: Extract HTTP header name/value pairs from HTTP responses
## Version: 1.0
## Priority: 20
## Sample: samples/http-headers/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Apply if input contains HTTP status line
    # Use while-read loop so ^ anchors match per-line (not start of entire string)
    while IFS= read -r line; do
        if [[ "$line" =~ ^HTTP/[0-9.]+" "[0-9][0-9][0-9] ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"

    local result=""
    local in_http=0

    while IFS= read -r line; do
        # Detect HTTP status line
        if [[ "$line" =~ ^HTTP/[0-9.]+" "[0-9][0-9][0-9] ]]; then
            in_http=1
            read -ra _arr <<< "$line"
            local status_code="${_arr[1]}"
            # status_text is everything after "HTTP/x.x NNN "
            local after_proto="${line#HTTP/*/[0-9]* }"
            local status_text="${line#*"$status_code" }"
            if [[ "$status_text" == "$line" ]]; then
                status_text=""
            fi
            result+="HTTP-Status ${status_code}"$'\n'
            [[ -n "$status_text" ]] && result+="HTTP-Status-Text ${status_text}"$'\n'
            continue
        fi

        # Empty line ends HTTP headers
        if [[ $in_http -eq 1 && -z "$line" ]]; then
            in_http=0
            continue
        fi

        # Parse header lines
        if [[ $in_http -eq 1 ]]; then
            # Standard header format: Header-Name: value
            if [[ "$line" =~ ^[A-Za-z][A-Za-z0-9-]*: ]]; then
                local key="${line%%:*}"
                local value="${line#*: }"
                # If there was no space after colon, try without space
                if [[ "$value" == "$line" ]]; then
                    value="${line#*:}"
                fi
                # Trim leading spaces from value
                while [[ "$value" == " "* ]]; do value="${value# }"; done
                [[ -z "$value" ]] && continue
                result+="${key} ${value}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
