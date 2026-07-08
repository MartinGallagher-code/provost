#!/bin/bash
## Name: beff
## Description: Extract b_eff effective MPI bandwidth benchmark results
## Version: 1.0
## Priority: 10
## Sample: samples/beff/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"b_eff"* ]]; then
        return 0
    fi
    if [[ "$text" == *"effective bandwidth"* ]] && [[ "$text" == *"ring"* ]]; then
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

        # b_eff value: "b_eff = 1234.56 MB/s" or "b_eff =  1234.56"
        if [[ "$line" == *"b_eff"*"="* ]]; then
            # Skip lines that are sub-metrics (ring, random) unless no main value yet
            if [[ "$line" == *"ring"* ]] || [[ "$line" == *"random"* ]]; then
                # Handle ring/random specific b_eff lines
                if [[ "$line" == *"ring"* ]]; then
                    local _val="${line##*=}"
                    while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
                    read -ra _arr <<< "$_val"
                    [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="ring_bandwidth ${_arr[0]}"$'\n'
                fi
                if [[ "$line" == *"random"* ]]; then
                    local _val="${line##*=}"
                    while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
                    read -ra _arr <<< "$_val"
                    [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="random_bandwidth ${_arr[0]}"$'\n'
                fi
                continue
            fi
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="b_eff_value ${_arr[0]}"$'\n'
            continue
        fi

        # Ring bandwidth: "ring bandwidth = 1234.56 MB/s" (without b_eff prefix)
        if [[ "$line" == *"ring"*"bandwidth"*"="* ]] || [[ "$line" == *"Ring"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="ring_bandwidth ${_arr[0]}"$'\n'
            continue
        fi

        # Random bandwidth: "random bandwidth = 987.65 MB/s"
        if [[ "$line" == *"random"*"bandwidth"*"="* ]] || [[ "$line" == *"Random"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="random_bandwidth ${_arr[0]}"$'\n'
            continue
        fi

        # Number of processes: "Number of processes = 8" or "nprocs = 8"
        if [[ "$line" == *"processes"*"="* ]] || [[ "$line" == *"nprocs"*"="* ]] || [[ "$line" == *"Number of"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="num_processes ${_arr[0]}"$'\n'
            continue
        fi

        # Effective bandwidth (alternate format): "effective bandwidth: 1234.56 MB/s"
        if [[ "$line" == *"effective bandwidth"*":"* ]]; then
            local _val="${line##*:}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="b_eff_value ${_arr[0]}"$'\n'
            continue
        fi

        # Message length range: "msglen = 1 ... 4194304"
        if [[ "$line" == *"msglen"*"="* ]]; then
            local _val="${line##*=}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            [[ -n "$_val" ]] && result+="msglen_range ${_val}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
