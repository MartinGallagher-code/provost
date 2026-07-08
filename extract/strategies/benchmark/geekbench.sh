#!/bin/bash
## Name: geekbench
## Description: Extract benchmark scores from Geekbench text output
## Version: 1.0
## Priority: 10
## Sample: samples/geekbench/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    if [[ "$text" == *"Geekbench"* ]]; then
        if [[ "$text" =~ Single-Core\ Score|Multi-Core\ Score ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local test_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Score lines: "Single-Core Score    1234"
        if [[ "$line" == *"Single-Core Score"* ]]; then
            read -ra _arr <<< "$line"
            local score="${_arr[${#_arr[@]}-1]}"
            [[ -n "$score" ]] && result+="single_core_score ${score}"$'\n'
            continue
        fi
        if [[ "$line" == *"Multi-Core Score"* ]]; then
            read -ra _arr <<< "$line"
            local score="${_arr[${#_arr[@]}-1]}"
            [[ -n "$score" ]] && result+="multi_core_score ${score}"$'\n'
            continue
        fi

        # System info: "System Information" section
        if [[ "$line" == *"Operating System"* ]]; then
            local val="${line##*Operating System}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="operating_system ${val}"$'\n'
            continue
        fi
        if [[ "$line" == *"Model"* ]] && [[ "$line" != *"Model Name"* ]]; then
            local val="${line##*Model}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="model ${val}"$'\n'
            continue
        fi
        if [[ "$line" == *"Processor"* ]]; then
            local val="${line##*Processor}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="processor ${val}"$'\n'
            continue
        fi

        # Individual test scores: "  AES-XTS              1234"
        # Detect by indentation + name + numeric score at end
        if [[ "$line" =~ ^[[:space:]]{2,}[A-Za-z].*[0-9]+$ ]]; then
            read -ra _arr <<< "$line"
            local test_score="${_arr[${#_arr[@]}-1]}"
            # Build test name from all words except the last
            local test_name=""
            local _i
            for ((_i=0; _i<${#_arr[@]}-1; _i++)); do
                if [[ -n "$test_name" ]]; then
                    test_name+="_${_arr[$_i]}"
                else
                    test_name="${_arr[$_i]}"
                fi
            done
            if [[ "$test_score" =~ ^[0-9]+$ ]] && [[ -n "$test_name" ]]; then
                test_num=$((test_num + 1))
                result+="test${test_num}.name ${test_name}"$'\n'
                result+="test${test_num}.score ${test_score}"$'\n'
            fi
            continue
        fi
    done <<< "$text"

    echo "$result"
}
