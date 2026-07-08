#!/bin/bash
## Name: warc-headers
## Description: Extract WARC record metadata fields from WARC format files
## Version: 1.0
## Priority: 22
## Sample: samples/warc-headers/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Apply if input starts with or contains WARC version line
    [[ "$text" =~ (^|$'\n')WARC/ ]]
}

strategy_extract () {
    local text="$1"

    local result=""
    local in_warc=0

    while IFS= read -r line; do
        # Detect WARC version line
        if [[ "$line" =~ ^WARC/[0-9.]+$ ]]; then
            in_warc=1
            local version="${line#WARC/}"
            result+="WARC-Version ${version}"$'\n'
            continue
        fi

        # Empty line ends WARC headers
        if [[ $in_warc -eq 1 && -z "$line" ]]; then
            in_warc=0
            continue
        fi

        # Parse WARC header lines
        if [[ $in_warc -eq 1 ]]; then
            if [[ "$line" =~ ^[A-Za-z][A-Za-z0-9-]*: ]]; then
                local key value
                key="${line%%:*}"
                value="${line#*: }"
                # If there was no space after colon, try without space
                if [[ "$value" == "$line" ]]; then
                    value="${line#*:}"
                    while [[ "$value" == " "* ]]; do value="${value# }"; done
                fi

                # Skip empty values
                [[ -z "$value" ]] && continue

                result+="${key} ${value}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
