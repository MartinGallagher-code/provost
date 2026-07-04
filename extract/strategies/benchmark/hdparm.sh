#!/bin/bash
## Name: hdparm
## Description: Extract disk timing and cache read speeds from hdparm output
## Version: 1.0
## Priority: 15
## Sample: samples/hdparm/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    if [[ "$text" == *"/dev/"* ]]; then
        if [[ "$text" == *"Timing cached reads"* ]] || \
           [[ "$text" == *"Timing buffered disk reads"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_device=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Device line: "/dev/sda:"
        if [[ "$line" =~ ^/dev/ ]]; then
            current_device="${line%%:*}"
            current_device="${current_device#/dev/}"
            result+="device ${current_device}"$'\n'
            continue
        fi

        # Timing cached reads: "Timing cached reads:   12345 MB in  2.00 seconds = 6172.50 MB/sec"
        if [[ "$line" == *"Timing cached reads"* ]]; then
            local speed=""
            # Extract value after "= " and before " MB/sec"
            if [[ "$line" =~ =\ *([0-9.]+)\ *MB/sec ]]; then
                speed="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$current_device" ]]; then
                result+="${current_device}.cached_reads_MB_per_s ${speed}"$'\n'
            else
                result+="cached_reads_MB_per_s ${speed}"$'\n'
            fi
            continue
        fi

        # Timing buffered disk reads: "Timing buffered disk reads: 456 MB in  3.01 seconds = 151.50 MB/sec"
        if [[ "$line" == *"Timing buffered disk reads"* ]]; then
            local speed=""
            # Extract value after "= " and before " MB/sec"
            if [[ "$line" =~ =\ *([0-9.]+)\ *MB/sec ]]; then
                speed="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$current_device" ]]; then
                result+="${current_device}.buffered_reads_MB_per_s ${speed}"$'\n'
            else
                result+="buffered_reads_MB_per_s ${speed}"$'\n'
            fi
            continue
        fi
    done <<< "$text"

    echo "$result"
}
