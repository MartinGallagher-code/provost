#!/bin/bash
## Name: redis-benchmark
## Description: Extract throughput, latency, and config from redis-benchmark output
## Version: 1.0
## Priority: 12
## Sample: samples/redis-benchmark/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Must have ====== COMMAND ====== section headers
    # Use variable for regex: bash [[ =~ ]] $ only matches end-of-string, not end-of-line
    local _nl=$'\n'
    local _re="(^|${_nl})====== .+ ======(${_nl}|$)"
    [[ "$text" =~ $_re ]] || return 1
    # Must have "requests completed in" indicator
    [[ "$text" == *"requests completed in"* ]] || return 1
    # Must have throughput summary
    [[ "$text" == *"throughput summary"* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local cmd_num=0
    local prefix=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Section header: ====== PING_INLINE ======
        if [[ "$line" =~ ^======\ .+\ ======$ ]]; then
            cmd_num=$((cmd_num + 1))
            prefix=""
            if [[ $cmd_num -gt 1 ]]; then
                prefix="cmd${cmd_num}."
            fi
            local cmd_name
            cmd_name=$(_strat_redis_bench_extract_command "$line")
            [[ -n "$cmd_name" ]] && result+="${prefix}command ${cmd_name}"$'\n'
            continue
        fi

        # Skip lines before the first command section
        [[ $cmd_num -eq 0 ]] && continue

        # "100000 requests completed in 1.23 seconds"
        if [[ "$line" == *"requests completed in"* ]]; then
            read -ra _arr <<< "$line"
            local requests="${_arr[0]}"
            # Extract time: after "completed in ", first word
            local _after="${line#*completed in }"
            read -ra _arr2 <<< "$_after"
            local time_s="${_arr2[0]}"
            [[ -n "$requests" ]] && result+="${prefix}requests ${requests}"$'\n'
            [[ -n "$time_s" ]] && result+="${prefix}time_seconds ${time_s}"$'\n'
            continue
        fi

        # "50 parallel clients"
        if [[ "$line" == *"parallel clients"* ]]; then
            read -ra _arr <<< "$line"
            local clients="${_arr[0]}"
            [[ -n "$clients" ]] && result+="${prefix}parallel_clients ${clients}"$'\n'
            continue
        fi

        # "3 bytes payload"
        if [[ "$line" == *"bytes payload"* ]]; then
            read -ra _arr <<< "$line"
            local payload="${_arr[0]}"
            [[ -n "$payload" ]] && result+="${prefix}payload_bytes ${payload}"$'\n'
            continue
        fi

        # "throughput summary: 81300.81 requests per second"
        if [[ "$line" == *"throughput summary"* ]]; then
            local _after="${line#*throughput summary: }"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _arr <<< "$_after"
            local rps="${_arr[0]}"
            [[ -n "$rps" ]] && result+="${prefix}throughput_rps ${rps}"$'\n'
            continue
        fi

        # Latency summary table line (avg/min/p50/p95/p99/max values)
        # Line looks like: "        0.103     0.024     0.103     0.159     0.287     0.879"
        # It follows the header: "          avg       min       p50       p95       p99       max"
        if _strat_redis_bench_is_latency_values "$line"; then
            read -ra _arr <<< "$line"
            local avg="${_arr[0]}"
            local min="${_arr[1]}"
            local p50="${_arr[2]}"
            local p95="${_arr[3]}"
            local p99="${_arr[4]}"
            local max="${_arr[5]}"
            [[ -n "$avg" ]] && result+="${prefix}latency_avg_ms ${avg}"$'\n'
            [[ -n "$min" ]] && result+="${prefix}latency_min_ms ${min}"$'\n'
            [[ -n "$p50" ]] && result+="${prefix}latency_p50_ms ${p50}"$'\n'
            [[ -n "$p95" ]] && result+="${prefix}latency_p95_ms ${p95}"$'\n'
            [[ -n "$p99" ]] && result+="${prefix}latency_p99_ms ${p99}"$'\n'
            [[ -n "$max" ]] && result+="${prefix}latency_max_ms ${max}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}

# Extract command name from "====== PING_INLINE ======"
_strat_redis_bench_extract_command () {
    local line="$1"
    line="${line#====== }"
    line="${line% ======}"
    echo "$line"
}

# Extract Nth whitespace-delimited field from a line (after trimming leading spaces)
_strat_redis_bench_field () {
    read -ra _arr <<< "$1"
    local idx=$(($2 - 1))
    echo "${_arr[$idx]}"
}

# Check if a line is a latency values row (6 decimal numbers)
_strat_redis_bench_is_latency_values () {
    local line="$1"
    # Must have exactly 6 fields, all numeric (decimal)
    read -ra _arr <<< "$line"
    [[ ${#_arr[@]} -eq 6 ]] || return 1
    # All fields must be numeric (decimal)
    [[ "$line" =~ ^[\ ]*[0-9]+\.[0-9]+[\ ]+[0-9]+\.[0-9]+[\ ]+[0-9]+\.[0-9]+[\ ]+[0-9]+\.[0-9]+[\ ]+[0-9]+\.[0-9]+[\ ]+[0-9]+\.[0-9]+[\ ]*$ ]]
}
