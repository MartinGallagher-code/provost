#!/bin/bash
## Name: osu-micro
## Description: Extract OSU Micro-Benchmarks results (bandwidth, latency, collective ops)
## Version: 1.0
## Priority: 10
## Sample: samples/osu-micro/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"OSU MPI"* ]] || [[ "$text" == *"osu_"* ]]; then
        return 0
    fi
    if [[ "$text" == *"# OSU"* ]]; then
        return 0
    fi
    # Fallback: typical OSU table header with Size column
    if [[ "$text" == *"# Size"* ]] && [[ "$text" == *"Latency"* || "$text" == *"Bandwidth"* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract benchmark name from header line
    # e.g. "# OSU MPI Latency Test v5.6.2" or "# OSU MPI Bi-Directional Bandwidth Test"
    local bench_name=""
    while IFS= read -r line; do
        if [[ "$line" == *"# OSU"* ]]; then
            local _after="${line#*# OSU }"
            # Strip version info
            _after="${_after% v[0-9]*}"
            _after="${_after% V[0-9]*}"
            bench_name="$_after"
            break
        fi
        # Also check for "osu_bw", "osu_latency" etc. in command lines
        if [[ "$line" == *"osu_"* ]] && [[ -z "$bench_name" ]]; then
            local _tmp="$line"
            # Extract the osu_xxx part
            _tmp="${_tmp##*osu_}"
            read -ra _arr <<< "$_tmp"
            bench_name="osu_${_arr[0]}"
        fi
    done <<< "$text"
    [[ -n "$bench_name" ]] && result+="benchmark_name ${bench_name}"$'\n'

    # Determine type: bandwidth or latency based on header
    local col_type=""
    local header_line=""
    while IFS= read -r line; do
        if [[ "$line" == "# Size"* ]]; then
            header_line="$line"
            if [[ "$line" == *"Bandwidth"* ]]; then
                col_type="bandwidth"
            elif [[ "$line" == *"Latency"* || "$line" == *"Avg Latency"* ]]; then
                col_type="latency"
            fi
            break
        fi
    done <<< "$text"

    # Check for min/max/avg columns in header
    local has_minmaxavg=0
    if [[ "$header_line" == *"Min Latency"* ]] || [[ "$header_line" == *"Max Latency"* ]]; then
        has_minmaxavg=1
    fi

    # Parse data rows: two-column (size value) or multi-column (size avg min max iter)
    local row_num=0
    local in_data=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip comment/header lines
        [[ "$line" == "#"* ]] && { in_data=1; continue; }
        [[ $in_data -eq 0 ]] && continue

        # Data rows are numeric: "1   1.23" or "4096   2345.67"
        read -ra _arr <<< "$line"
        local size="${_arr[0]}"
        [[ "$size" =~ ^[0-9] ]] || continue

        row_num=$((row_num + 1))

        result+="row${row_num}.size ${size}"$'\n'

        if [[ "$col_type" == "bandwidth" ]]; then
            [[ -n "${_arr[1]}" ]] && result+="row${row_num}.bandwidth_MB_s ${_arr[1]}"$'\n'
        elif [[ "$col_type" == "latency" ]]; then
            if [[ $has_minmaxavg -eq 1 ]] && [[ ${#_arr[@]} -ge 4 ]]; then
                [[ -n "${_arr[1]}" ]] && result+="row${row_num}.avg_latency_us ${_arr[1]}"$'\n'
                [[ -n "${_arr[2]}" ]] && result+="row${row_num}.min_latency_us ${_arr[2]}"$'\n'
                [[ -n "${_arr[3]}" ]] && result+="row${row_num}.max_latency_us ${_arr[3]}"$'\n'
                [[ -n "${_arr[4]}" ]] && result+="row${row_num}.iterations ${_arr[4]}"$'\n'
            else
                [[ -n "${_arr[1]}" ]] && result+="row${row_num}.latency_us ${_arr[1]}"$'\n'
            fi
        else
            # Generic: just output value column
            [[ -n "${_arr[1]}" ]] && result+="row${row_num}.value ${_arr[1]}"$'\n'
        fi

        # If there are extra columns beyond basic two, capture them
        if [[ ${#_arr[@]} -ge 3 ]] && [[ "$col_type" != "latency" || $has_minmaxavg -eq 0 ]]; then
            [[ -n "${_arr[2]}" ]] && result+="row${row_num}.col3 ${_arr[2]}"$'\n'
        fi
    done <<< "$text"

    [[ $row_num -gt 0 ]] && result+="total_rows ${row_num}"$'\n'

    echo "$result"
}
