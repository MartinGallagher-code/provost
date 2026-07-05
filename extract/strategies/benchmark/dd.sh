#!/bin/bash
## Name: dd
## Description: Extract bytes copied, time, and throughput from dd output
## Version: 1.0
## Priority: 12
## Sample: samples/dd/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    # Linux: "bytes (X MB, Y GB) copied, N s, Z MB/s"
    if [[ "$text" =~ [0-9]+\ bytes.*copied ]]; then
        return 0
    fi
    # macOS: "bytes transferred in N secs (Z bytes/sec)"
    if [[ "$text" == *"bytes transferred"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Linux format: 1073741824 bytes (1.0 GB, 1024 MiB) copied, 2.345 s, 458 MB/s
        if [[ "$line" =~ [0-9]+\ bytes.*copied ]]; then
            read -ra _arr <<< "$line"
            local bytes="${_arr[0]}"
            # Extract time and throughput after "copied, "
            local _after="${line##*copied, }"
            read -ra _arr2 <<< "$_after"
            local time_s="${_arr2[0]}"
            local throughput="${_arr2[2]}_${_arr2[3]}"
            [[ -n "$bytes" ]] && result+="bytes_copied ${bytes}"$'\n'
            [[ -n "$time_s" ]] && result+="time_seconds ${time_s}"$'\n'
            [[ -n "$throughput" && "$throughput" != "_" ]] && result+="throughput ${throughput}"$'\n'
            continue
        fi

        # macOS format: 1073741824 bytes transferred in 2.345 secs (457834496 bytes/sec)
        if [[ "$line" == *"bytes transferred"* ]]; then
            read -ra _arr <<< "$line"
            local bytes="${_arr[0]}"
            # Extract time after "transferred in "
            local _after="${line##*transferred in }"
            read -ra _arr2 <<< "$_after"
            local time_s="${_arr2[0]}"
            # Extract throughput from parentheses
            local throughput=""
            local _paren_re='\(([^)]*)\)'
            if [[ "$line" =~ $_paren_re ]]; then
                throughput="${BASH_REMATCH[1]}"
                throughput="${throughput// /_}"
            fi
            [[ -n "$bytes" ]] && result+="bytes_transferred ${bytes}"$'\n'
            [[ -n "$time_s" ]] && result+="time_seconds ${time_s}"$'\n'
            [[ -n "$throughput" ]] && result+="throughput ${throughput}"$'\n'
            continue
        fi

        # records in/out lines: "2097152+0 records in"
        if [[ "$line" =~ ^[0-9]+\+[0-9]+\ records ]]; then
            read -ra _arr <<< "$line"
            local count="${_arr[0]}"
            count="${count%%+*}"
            local direction="${_arr[2]}"
            if [[ "$direction" == "in" ]]; then
                result+="records_in ${count}"$'\n'
            elif [[ "$direction" == "out" ]]; then
                result+="records_out ${count}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
