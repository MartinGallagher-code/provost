#!/bin/bash
## Name: hpcg
## Description: Extract HPCG (High Performance Conjugate Gradients) benchmark results
## Version: 1.0
## Priority: 10
## Sample: samples/hpcg/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"HPCG"* ]]; then
        if [[ "$text" == *"GFLOP/s"* || "$text" == *"Conjugate Gradient"* || "$text" == *"Final Summary"* ]]; then
            _STRATEGY_CONFIDENCE=95
            return 0
        fi
        return 0
    fi
    if [[ "$text" == *"High Performance Conjugate Gradient"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # GFLOP/s rating: "HPCG result is VALID with a GFLOP/s rating of=123.456"
        # or "GFLOP/s Summary::Total=123.456"
        if [[ "$line" == *"GFLOP/s"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ -n "${_arr[0]}" ]] && result+="gflops ${_arr[0]}"$'\n'
            continue
        fi
        if [[ "$line" == *"GFLOP/s"*":"* ]] && [[ "$line" != *"="* ]]; then
            local _val="${line##*:}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="gflops ${_arr[0]}"$'\n'
            continue
        fi

        # Problem size: "Global Problem Dimensions are 104 x 104 x 104"
        # or "nx=104" / "ny=104" / "nz=104"
        if [[ "$line" == *"Global Problem Dimensions"* ]]; then
            local _after="${line##*are }"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            result+="problem_size ${_after}"$'\n'
            continue
        fi
        if [[ "$line" == *"nx="* ]] && [[ "$line" != *"ny="* ]]; then
            local _val="${line##*nx=}"
            read -ra _arr <<< "$_val"
            [[ -n "${_arr[0]}" ]] && result+="nx ${_arr[0]}"$'\n'
            continue
        fi
        if [[ "$line" == *"ny="* ]] && [[ "$line" != *"nx="* ]]; then
            local _val="${line##*ny=}"
            read -ra _arr <<< "$_val"
            [[ -n "${_arr[0]}" ]] && result+="ny ${_arr[0]}"$'\n'
            continue
        fi
        if [[ "$line" == *"nz="* ]] && [[ "$line" != *"nx="* ]]; then
            local _val="${line##*nz=}"
            read -ra _arr <<< "$_val"
            [[ -n "${_arr[0]}" ]] && result+="nz ${_arr[0]}"$'\n'
            continue
        fi

        # Time: "Total Time=12.345" or "Benchmark Time Summary::Total=12.345"
        if [[ "$line" == *"Total Time"*"="* ]] || [[ "$line" == *"Time Summary"*"Total="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="time_seconds ${_arr[0]}"$'\n'
            continue
        fi

        # Memory: "Total memory used for data=1.23 GB" or "Memory Use Information::Total memory"
        if [[ "$line" == *"memory"*"="* ]] || [[ "$line" == *"Memory"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            if [[ "${_arr[0]}" =~ ^[0-9] ]]; then
                local mem_val="${_arr[0]}"
                local mem_unit="${_arr[1]}"
                [[ -n "$mem_unit" ]] && mem_val="${mem_val}_${mem_unit}"
                result+="memory ${mem_val}"$'\n'
            fi
            continue
        fi

        # Convergence: "Scaled Residual [1.23e-15]" or "Convergence=1" or iterations
        if [[ "$line" == *"Convergence"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ -n "${_arr[0]}" ]] && result+="convergence ${_arr[0]}"$'\n'
            continue
        fi
        if [[ "$line" == *"Scaled Residual"* ]]; then
            local _val="${line##*[}"
            _val="${_val%%]*}"
            [[ -n "$_val" ]] && result+="scaled_residual ${_val}"$'\n'
            continue
        fi
        if [[ "$line" == *"Number of CG sets"*"="* ]] || [[ "$line" == *"iterations"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="iterations ${_arr[0]}"$'\n'
            continue
        fi

        # Validity
        if [[ "$line" == *"VALID"* ]]; then
            result+="validity VALID"$'\n'
            continue
        fi
        if [[ "$line" == *"INVALID"* ]]; then
            result+="validity INVALID"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
