#!/bin/bash
## Name: netperf
## Description: Extract network performance results from netperf output
## Version: 1.0
## Priority: 12
## Sample: samples/netperf/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    if [[ "$text" == *"MIGRATED"* ]]; then
        if [[ "$text" == *"Throughput"* || "$text" == *"Trans"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Test type: "MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to ..."
    local test_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"MIGRATED"* ]]; then
            test_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$test_line" ]]; then
        local test_type
        # Extract test name between MIGRATED and TEST
        local after="${test_line#*MIGRATED }"
        test_type="${after%% TEST*}"
        [[ -n "$test_type" ]] && result+="test_type ${test_type}"$'\n'
    fi

    # Header + data lines -- netperf prints a header then one data line
    # Find the last numeric line (data row)
    local data_line=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ "$trimmed" =~ ^[0-9] ]]; then
            data_line="$line"
        fi
    done <<< "$text"

    if [[ -n "$data_line" ]]; then
        local fields=()
        read -ra fields <<< "$data_line"

        # Detect format by checking test type or field count
        local text_upper
        text_upper=$(echo "$text" | tr '[:lower:]' '[:upper:]')
        if [[ "$text_upper" == *"STREAM"* ]]; then
            # TCP_STREAM: recv_size send_size msg_size elapsed throughput
            [[ -n "${fields[0]:-}" ]] && result+="recv_socket_size ${fields[0]}"$'\n'
            [[ -n "${fields[1]:-}" ]] && result+="send_socket_size ${fields[1]}"$'\n'
            [[ -n "${fields[2]:-}" ]] && result+="send_message_size ${fields[2]}"$'\n'
            [[ -n "${fields[3]:-}" ]] && result+="elapsed_time ${fields[3]}"$'\n'
            [[ -n "${fields[4]:-}" ]] && result+="throughput_Mbps ${fields[4]}"$'\n'
        elif [[ "$text_upper" == *"_RR"* ]]; then
            # TCP_RR: send_size recv_size request_size response_size elapsed trans_rate
            [[ -n "${fields[0]:-}" ]] && result+="local_socket_size ${fields[0]}"$'\n'
            [[ -n "${fields[1]:-}" ]] && result+="remote_socket_size ${fields[1]}"$'\n'
            [[ -n "${fields[2]:-}" ]] && result+="request_size ${fields[2]}"$'\n'
            [[ -n "${fields[3]:-}" ]] && result+="response_size ${fields[3]}"$'\n'
            [[ -n "${fields[4]:-}" ]] && result+="elapsed_time ${fields[4]}"$'\n'
            [[ -n "${fields[5]:-}" ]] && result+="transactions_per_sec ${fields[5]}"$'\n'
        else
            # Generic: output positional fields
            local i
            for ((i=0; i<${#fields[@]}; i++)); do
                result+="field$((i+1)) ${fields[$i]}"$'\n'
            done
        fi
    fi

    echo "$result"
}
