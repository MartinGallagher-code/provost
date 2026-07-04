#!/bin/bash
## Name: npb
## Description: Extract NAS Parallel Benchmarks results
## Version: 1.0
## Priority: 10
## Sample: samples/npb/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"NAS Parallel"* ]]; then
        return 0
    fi
    if [[ "$text" == *"NPB"* ]] && [[ "$text" == *"Class"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Mop/s total"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Benchmark name: "NAS Parallel Benchmarks (NPB3.4-MPI) - CG Benchmark"
        # or " Benchmark Completed." preceded by benchmark type
        if [[ "$line" == *"NAS Parallel Benchmarks"*"-"*"Benchmark"* ]]; then
            local _after="${line##*- }"
            _after="${_after% Benchmark*}"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            [[ -n "$_after" ]] && result+="benchmark ${_after}"$'\n'
            continue
        fi

        # Class: " Class   =  C" or "Class =  B"
        if [[ "$line" == *"Class"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ -n "${_arr[0]}" ]] && result+="class ${_arr[0]}"$'\n'
            continue
        fi

        # Size: " Size   =   32x  32x  32" or "Size    =    1048576"
        if [[ "$line" == *"Size"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            # Collapse multiple spaces to single space
            _val="$(echo "$_val" | tr -s ' ')"
            # Replace "x " with "x" for dimension notation
            _val="${_val// x /x}"
            read -ra _arr <<< "$_val"
            [[ -n "${_arr[0]}" ]] && result+="size ${_arr[0]}"$'\n'
            continue
        fi

        # Iterations: " Iterations  =  15"
        if [[ "$line" == *"Iterations"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="iterations ${_arr[0]}"$'\n'
            continue
        fi

        # Time in seconds: " Time in seconds =  12.34"
        if [[ "$line" == *"Time in seconds"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="time_seconds ${_arr[0]}"$'\n'
            continue
        fi

        # Mop/s total: " Mop/s total     =  1234.56"
        if [[ "$line" == *"Mop/s total"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="mops_total ${_arr[0]}"$'\n'
            continue
        fi

        # Mop/s/process: " Mop/s/process   =  308.64"
        if [[ "$line" == *"Mop/s/process"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="mops_per_process ${_arr[0]}"$'\n'
            continue
        fi

        # Number of processes: " No. of processes =  4"
        if [[ "$line" == *"No."*"process"*"="* ]] || [[ "$line" == *"processes"*"="* ]] || [[ "$line" == *"Total processes"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="num_processes ${_arr[0]}"$'\n'
            continue
        fi

        # Verification: " Verification    =  SUCCESSFUL" or "UNSUCCESSFUL"
        if [[ "$line" == *"Verification"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ -n "${_arr[0]}" ]] && result+="verification ${_arr[0]}"$'\n'
            continue
        fi

        # Operation type: " Operation type  =  floating point"
        if [[ "$line" == *"Operation type"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            _val="$(echo "$_val" | tr ' ' '_')"
            [[ -n "$_val" ]] && result+="operation_type ${_val}"$'\n'
            continue
        fi

        # Compiler version info
        if [[ "$line" == *"Compiler version"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            [[ -n "$_val" ]] && result+="compiler_version ${_val}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
