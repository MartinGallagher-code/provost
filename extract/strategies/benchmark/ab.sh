#!/bin/bash
## Name: ab
## Description: Extract HTTP load test results from Apache Bench (ab) output
## Version: 1.0
## Priority: 10
## Sample: samples/ab/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"ApacheBench"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Server Software:"* ]] && \
       [[ "$text" == *"Requests per second:"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Key: Value format lines
        case "$line" in
            *"Server Software:"*)
                result+="server_software $(_strat_ab_extract_value "$line")"$'\n' ;;
            *"Server Hostname:"*)
                result+="server_hostname $(_strat_ab_extract_value "$line")"$'\n' ;;
            *"Server Port:"*)
                result+="server_port $(_strat_ab_extract_value "$line")"$'\n' ;;
            *"Document Path:"*)
                result+="document_path $(_strat_ab_extract_value "$line")"$'\n' ;;
            *"Document Length:"*)
                local _val
                _val=$(_strat_ab_extract_value "$line")
                result+="document_length ${_val// /_}"$'\n' ;;
            *"Concurrency Level:"*)
                result+="concurrency_level $(_strat_ab_extract_value "$line")"$'\n' ;;
            *"Time taken for tests:"*)
                local _val
                _val=$(_strat_ab_extract_value "$line")
                result+="time_taken ${_val// /_}"$'\n' ;;
            *"Complete requests:"*)
                result+="complete_requests $(_strat_ab_extract_value "$line")"$'\n' ;;
            *"Failed requests:"*)
                result+="failed_requests $(_strat_ab_extract_value "$line")"$'\n' ;;
            *"Total transferred:"*)
                local _val
                _val=$(_strat_ab_extract_value "$line")
                result+="total_transferred ${_val// /_}"$'\n' ;;
            *"HTML transferred:"*)
                local _val
                _val=$(_strat_ab_extract_value "$line")
                result+="html_transferred ${_val// /_}"$'\n' ;;
            *"Requests per second:"*)
                local _val
                _val=$(_strat_ab_extract_value "$line")
                read -ra _arr <<< "$_val"
                result+="requests_per_second ${_arr[0]}"$'\n' ;;
            *"Time per request:"*"(mean)"*)
                local _val
                _val=$(_strat_ab_extract_value "$line")
                read -ra _arr <<< "$_val"
                result+="time_per_request_ms ${_arr[0]}"$'\n' ;;
            *"Time per request:"*"concurrent"*)
                local _val
                _val=$(_strat_ab_extract_value "$line")
                read -ra _arr <<< "$_val"
                result+="time_per_request_concurrent_ms ${_arr[0]}"$'\n' ;;
            *"Transfer rate:"*)
                local _val
                _val=$(_strat_ab_extract_value "$line")
                result+="transfer_rate ${_val// /_}"$'\n' ;;
        esac
    done <<< "$text"

    echo "$result"
}

_strat_ab_extract_value () {
    local line="$1"
    # Remove everything up to and including first ": "
    local _val="${line#*: }"
    # Strip leading spaces
    while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
    echo "$_val"
}
