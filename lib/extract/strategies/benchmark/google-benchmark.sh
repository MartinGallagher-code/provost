#!/bin/bash
## Name: google-benchmark
## Description: Extract benchmark names, times, CPU, and iterations from Google Benchmark console output
## Version: 1.0
## Priority: 10
## Sample: samples/google-benchmark/basic.txt

# Helper: parse the metadata header (Run on, CPU Caches)
_strat_google_benchmark_extract_metadata () {
    local text="$1"
    local result=""

    # Extract CPU info from "Run on (N X freq MHz CPU s)" line
    local run_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == "Run on"* ]]; then
            run_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$run_line" ]]; then
        local cpu_info="${run_line#Run on }"
        cpu_info="${cpu_info// /_}"
        result+="cpu_info ${cpu_info}"$'\n'
    fi

    # Extract cache info lines: "  L1 Data 32 KiB (x8)" etc.
    local cache_num=0
    while IFS= read -r cline; do
        [[ -z "$cline" ]] && continue
        if [[ "$cline" =~ ^[[:space:]]+L[0-9] ]]; then
            cache_num=$((cache_num + 1))
            # Trim leading whitespace, replace spaces with underscores
            local cache_val="$cline"
            while [[ "$cache_val" == " "* ]]; do cache_val="${cache_val# }"; done
            cache_val="${cache_val// /_}"
            result+="cache${cache_num} ${cache_val}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

# Helper: parse the benchmark data table
_strat_google_benchmark_extract_table () {
    local text="$1"
    local result=""
    local bench_num=0

    # Find lines that look like benchmark data rows:
    # BM_Name/Param   <time> <unit>   <cpu> <unit>   <iterations>
    # Skip header lines, separator lines, and metadata
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip separator lines
        [[ "$line" == "-"* ]] && continue
        # Skip header line
        [[ "$line" == "Benchmark"* ]] && continue
        # Skip metadata lines (Run on, CPU Caches, etc.)
        [[ "$line" == "Run on"* ]] && continue
        [[ "$line" == "CPU"* ]] && continue
        [[ "$line" =~ ^[[:space:]]+L[0-9] ]] && continue

        # Try to parse as a benchmark data row
        # Format: BM_Name  <time> <unit>  <cpu> <unit>  <iterations>
        read -ra _arr <<< "$line"
        # ENV-115: short lines (preamble, separators) have < 6 fields — guard
        # reads so nounset doesn't trip before the validity check below.
        local bm_name="${_arr[0]:-}"
        local bm_time="${_arr[1]:-}"
        local bm_time_unit="${_arr[2]:-}"
        local bm_cpu="${_arr[3]:-}"
        local bm_cpu_unit="${_arr[4]:-}"
        local bm_iter="${_arr[5]:-}"

        # Validate: name should start with BM_ or a letter, time should be numeric
        [[ "$bm_name" =~ ^[A-Za-z] ]] || continue
        [[ "$bm_time" =~ ^[0-9] ]] || continue

        bench_num=$((bench_num + 1))
        result+="bench${bench_num}.name ${bm_name}"$'\n'
        result+="bench${bench_num}.time ${bm_time}_${bm_time_unit}"$'\n'
        result+="bench${bench_num}.cpu ${bm_cpu}_${bm_cpu_unit}"$'\n'
        result+="bench${bench_num}.iterations ${bm_iter}"$'\n'
    done <<< "$text"

    echo "$result"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    # Detect Google Benchmark output by looking for the table header or "Run on"
    # Use variable for regex: (^|newline) to match any line start
    local _nl=$'\n'
    local _re="(^|${_nl})Benchmark[[:space:]]*Time[[:space:]]*CPU"
    if [[ "$text" =~ $_re ]]; then
        return 0
    fi
    _re="(^|${_nl})Run on"
    if [[ "$text" =~ $_re ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract metadata (CPU info, caches)
    local meta
    meta=$(_strat_google_benchmark_extract_metadata "$text")
    if [[ -n "$meta" ]]; then
        result+="${meta}"$'\n'
    fi

    # Extract benchmark table data
    local table
    table=$(_strat_google_benchmark_extract_table "$text")
    if [[ -n "$table" ]]; then
        result+="${table}"$'\n'
    fi

    echo "$result"
}
