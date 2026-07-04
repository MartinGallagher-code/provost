#!/bin/bash
## Name: wrk
## Description: Extract HTTP benchmark results from wrk output
## Version: 1.0
## Priority: 12
## Sample: samples/wrk/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"Running"* ]] && \
       [[ "$text" == *"threads"* ]] && \
       [[ "$text" == *"connections"* ]]; then
        if [[ "$text" == *"Latency"* || "$text" == *"Req/Sec"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Header: "Running 30s test @ http://localhost:8080/api"
    #         "  4 threads and 100 connections"
    local header_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == "Running"* ]]; then
            header_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$header_line" ]]; then
        read -ra _arr <<< "$header_line"
        local duration="${_arr[1]}"
        local url="${_arr[${#_arr[@]}-1]}"
        [[ -n "$duration" ]] && result+="duration ${duration}"$'\n'
        [[ -n "$url" ]] && result+="url ${url}"$'\n'
    fi

    local threads_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"threads and"* ]]; then
            threads_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$threads_line" ]]; then
        read -ra _arr <<< "$threads_line"
        local threads="${_arr[0]}"
        local connections="${_arr[3]}"
        [[ -n "$threads" ]] && result+="threads ${threads}"$'\n'
        [[ -n "$connections" ]] && result+="connections ${connections}"$'\n'
    fi

    # Latency stats: "  Latency   250.12us   45.67us  1.23ms   99.12%"
    local latency_line=""
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^[\ ]*Latency[\ ] ]]; then
            latency_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$latency_line" ]]; then
        read -ra _arr <<< "$latency_line"
        local avg="${_arr[1]}"
        local stdev="${_arr[2]}"
        local max="${_arr[3]}"
        [[ -n "$avg" ]] && result+="latency_avg ${avg}"$'\n'
        [[ -n "$stdev" ]] && result+="latency_stdev ${stdev}"$'\n'
        [[ -n "$max" ]] && result+="latency_max ${max}"$'\n'
    fi

    # Req/Sec stats: "  Req/Sec    12.34k    1.23k   15.67k   78.90%"
    local reqsec_line=""
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^[\ ]*Req/Sec ]]; then
            reqsec_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$reqsec_line" ]]; then
        read -ra _arr <<< "$reqsec_line"
        local avg="${_arr[1]}"
        local stdev="${_arr[2]}"
        local max="${_arr[3]}"
        [[ -n "$avg" ]] && result+="req_per_sec_avg ${avg}"$'\n'
        [[ -n "$stdev" ]] && result+="req_per_sec_stdev ${stdev}"$'\n'
        [[ -n "$max" ]] && result+="req_per_sec_max ${max}"$'\n'
    fi

    # Latency distribution (with --latency flag):
    # "  50%  245.00us"
    # "  99%    1.23ms"
    while IFS= read -r line; do
        if [[ "$line" =~ ^[\ ]+[0-9]+% ]]; then
            read -ra _arr <<< "$line"
            local pct="${_arr[0]}"
            pct="${pct%\%}"
            local val="${_arr[1]}"
            [[ -n "$pct" && -n "$val" ]] && result+="latency_p${pct} ${val}"$'\n'
        fi
    done <<< "$text"

    # Summary: "12345 requests in 30.00s, 1.23MB read"
    local summary_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"requests in"* ]]; then
            summary_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$summary_line" ]]; then
        read -ra _arr <<< "$summary_line"
        local total_requests="${_arr[0]}"
        # Transfer: after comma
        local _after_comma="${summary_line#*, }"
        while [[ "$_after_comma" == " "* ]]; do _after_comma="${_after_comma# }"; done
        read -ra _arr2 <<< "$_after_comma"
        local total_transfer="${_arr2[0]}"
        [[ -n "$total_requests" ]] && result+="total_requests ${total_requests}"$'\n'
        [[ -n "$total_transfer" ]] && result+="total_transfer ${total_transfer}"$'\n'
    fi

    # Final metrics: "Requests/sec:  12345.67"
    local rps_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Requests/sec"* ]]; then
            rps_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$rps_line" ]]; then
        read -ra _arr <<< "$rps_line"
        local rps="${_arr[1]}"
        [[ -n "$rps" ]] && result+="requests_per_sec ${rps}"$'\n'
    fi

    # "Transfer/sec:    1.23MB"
    local tps_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Transfer/sec"* ]]; then
            tps_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$tps_line" ]]; then
        read -ra _arr <<< "$tps_line"
        local tps="${_arr[1]}"
        [[ -n "$tps" ]] && result+="transfer_per_sec ${tps}"$'\n'
    fi

    # Socket errors: "Socket errors: connect 0, read 5, write 0, timeout 2"
    local errors_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Socket errors"* ]]; then
            errors_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$errors_line" ]]; then
        # Extract "connect N" "read N" "write N" "timeout N"
        local _after="${errors_line#*connect }"
        local connect_err="${_after%%,*}"
        _after="${errors_line#*read }"
        local read_err="${_after%%,*}"
        _after="${errors_line#*write }"
        local write_err="${_after%%,*}"
        _after="${errors_line#*timeout }"
        read -ra _arr <<< "$_after"
        local timeout_err="${_arr[0]}"
        [[ -n "$connect_err" ]] && result+="socket_errors_connect ${connect_err}"$'\n'
        [[ -n "$read_err" ]] && result+="socket_errors_read ${read_err}"$'\n'
        [[ -n "$write_err" ]] && result+="socket_errors_write ${write_err}"$'\n'
        [[ -n "$timeout_err" ]] && result+="socket_errors_timeout ${timeout_err}"$'\n'
    fi

    echo "$result"
}
