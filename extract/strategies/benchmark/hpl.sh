#!/bin/bash
## Name: hpl
## Description: Extract High-Performance Linpack benchmark results
## Version: 1.0
## Priority: 10
## Sample: samples/hpl/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    if [[ "$text" == *"HPLinpack"* || "$text" == *"HPL"* ]]; then
        if [[ "$text" == *"Gflops"* || "$text" == *"gflops"* || "$text" == *"WR"* ]]; then
            return 0
        fi
    fi
    if [[ "$text" == *"High-Performance Linpack"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local run_num=0

    # Extract problem parameters: N, NB, P, Q
    local n_line=""
    # Also try: "N      :    1000"
    while IFS= read -r line; do
        if [[ "$line" == "N "* ]]; then
            n_line="$line"
            break
        fi
        if [[ "$line" == *"N"*":"* ]]; then
            n_line="$line"
            break
        fi
    done <<< "$text"

    # Results table: "WR00L2L2   1000   80  1  1   0.45   4.44e+00"
    # Columns: T/V  N  NB  P  Q  Time  Gflops
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # HPL result rows start with WR or similar
        if [[ "$line" =~ ^W[A-Z][0-9] ]]; then
            run_num=$((run_num + 1))
            local prefix=""
            if [[ $run_num -gt 1 ]]; then
                prefix="run${run_num}."
            fi

            local tv n nb p q time_s gflops
            read -ra _arr <<< "$line"
            tv="${_arr[0]}"
            n="${_arr[1]}"
            nb="${_arr[2]}"
            p="${_arr[3]}"
            q="${_arr[4]}"
            time_s="${_arr[5]}"
            gflops="${_arr[6]}"

            [[ -n "$n" ]] && result+="${prefix}n ${n}"$'\n'
            [[ -n "$nb" ]] && result+="${prefix}nb ${nb}"$'\n'
            [[ -n "$p" ]] && result+="${prefix}p ${p}"$'\n'
            [[ -n "$q" ]] && result+="${prefix}q ${q}"$'\n'
            [[ -n "$time_s" ]] && result+="${prefix}time_seconds ${time_s}"$'\n'
            [[ -n "$gflops" ]] && result+="${prefix}gflops ${gflops}"$'\n'
            continue
        fi

        # Residual check: "||Ax-b||_oo/(eps*(||A||_oo*||x||_oo+||b||_oo)*N)= 0.001234 ..PASSED"
        if [[ "$line" == *"PASSED"* || "$line" == *"FAILED"* ]]; then
            if [[ "$line" == *"PASSED"* ]]; then
                result+="residual_check PASSED"$'\n'
            else
                result+="residual_check FAILED"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
