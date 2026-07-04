#!/bin/bash
## Name: imb
## Description: Extract Intel MPI Benchmarks results (PingPong, Allreduce, etc.)
## Version: 1.0
## Priority: 10
## Sample: samples/imb/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"Intel(R) MPI Benchmarks"* ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ "$text" == *"IMB-"* ]]; then
        return 0
    fi
    if [[ "$text" == *"# Benchmarking"* ]] && [[ "$text" == *"#bytes"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_bench=""
    local bench_num=0
    local row_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # IMB version: "# Intel(R) MPI Benchmarks 2021.3, ..."
        if [[ "$line" == *"Intel(R) MPI Benchmarks"* ]]; then
            local _after="${line##*Benchmarks }"
            read -ra _arr <<< "$_after"
            local _ver="${_arr[0]}"
            _ver="${_ver%,}"
            [[ -n "$_ver" ]] && result+="imb_version ${_ver}"$'\n'
            continue
        fi

        # Number of processes: "# List of Benchmarks to run:" or "# #processes = 2"
        if [[ "$line" == *"#processes"*"="* ]] || [[ "$line" == *"# processes"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="num_processes ${_arr[0]}"$'\n'
            continue
        fi

        # Benchmark section: "# Benchmarking PingPong"
        if [[ "$line" == "# Benchmarking "* ]]; then
            local _name="${line#*# Benchmarking }"
            while [[ "$_name" == " "* ]]; do _name="${_name# }"; done
            while [[ "$_name" == *" " ]]; do _name="${_name% }"; done
            current_bench="$_name"
            bench_num=$((bench_num + 1))
            row_num=0
            result+="bench${bench_num}.name ${current_bench}"$'\n'
            continue
        fi

        # Skip header and comment lines
        [[ "$line" == "#"* ]] && continue

        # Data rows: "       0         1000       0.22       0.22       0.22       0.00"
        # Columns vary by benchmark type but generally:
        # bytes  repetitions  t_min[usec]  t_max[usec]  t_avg[usec]  Mbytes/sec
        [[ $bench_num -eq 0 ]] && continue

        read -ra _arr <<< "$line"
        local bytes="${_arr[0]}"
        [[ "$bytes" =~ ^[0-9] ]] || continue

        row_num=$((row_num + 1))
        local prefix="bench${bench_num}.row${row_num}"

        result+="${prefix}.bytes ${bytes}"$'\n'
        [[ -n "${_arr[1]}" ]] && result+="${prefix}.repetitions ${_arr[1]}"$'\n'

        if [[ ${#_arr[@]} -ge 6 ]]; then
            # Full row: bytes repetitions t_min t_max t_avg Mbytes/sec
            [[ -n "${_arr[2]}" ]] && result+="${prefix}.t_min_usec ${_arr[2]}"$'\n'
            [[ -n "${_arr[3]}" ]] && result+="${prefix}.t_max_usec ${_arr[3]}"$'\n'
            [[ -n "${_arr[4]}" ]] && result+="${prefix}.t_avg_usec ${_arr[4]}"$'\n'
            [[ -n "${_arr[5]}" ]] && result+="${prefix}.Mbytes_per_sec ${_arr[5]}"$'\n'
        elif [[ ${#_arr[@]} -ge 4 ]]; then
            # Shorter row: bytes repetitions t_avg Mbytes/sec
            [[ -n "${_arr[2]}" ]] && result+="${prefix}.t_avg_usec ${_arr[2]}"$'\n'
            [[ -n "${_arr[3]}" ]] && result+="${prefix}.Mbytes_per_sec ${_arr[3]}"$'\n'
        fi
    done <<< "$text"

    [[ $bench_num -gt 0 ]] && result+="total_benchmarks ${bench_num}"$'\n'

    echo "$result"
}
