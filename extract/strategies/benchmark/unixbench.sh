#!/bin/bash
## Name: unixbench
## Description: Extract benchmark scores from UnixBench output
## Version: 1.0
## Priority: 10
## Sample: samples/unixbench/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    if [[ "$text" == *"BYTE UNIX Benchmarks"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Benchmark Run:"* ]] && \
       [[ "$text" == *"Index Score"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local test_num=0

    # Extract parallel copies: "2 parallel copies of tests"
    local copies_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"parallel cop"* ]]; then
            copies_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$copies_line" ]]; then
        read -ra _arr <<< "$copies_line"
        local copies="${_arr[0]}"
        [[ -n "$copies" ]] && result+="parallel_copies ${copies}"$'\n'
    fi

    # Parse results table
    local in_index=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # System Benchmarks Index Score
        if [[ "$line" == *"System Benchmarks Index Score"* ]]; then
            read -ra _arr <<< "$line"
            local score="${_arr[${#_arr[@]}-1]}"
            if [[ "$score" =~ ^[0-9] ]]; then
                result+="system_index_score ${score}"$'\n'
            fi
            continue
        fi

        # Detect index table header
        if [[ "$line" == *"Index"* ]] && [[ "$line" == *"Score"* ]]; then
            in_index=1
            continue
        fi

        # Separator lines
        [[ "$line" == "==="* ]] && continue
        [[ "$line" == "---"* ]] && continue

        # Index table data rows
        if [[ $in_index -eq 1 ]]; then
            # Lines end with "   <score>   <index>"
            read -ra _arr <<< "$line"
            local nf=${#_arr[@]}
            local index_val="${_arr[$((nf-1))]}"
            # Validate index is numeric
            [[ "$index_val" =~ ^[0-9] ]] || continue

            local score_val="${_arr[$((nf-2))]}"
            # Extract test name: everything except the last two fields
            # Rebuild from array minus last 2 elements
            local test_name=""
            local i
            for ((i=0; i<nf-2; i++)); do
                if [[ -z "$test_name" ]]; then
                    test_name="${_arr[$i]}"
                else
                    test_name="${test_name}_${_arr[$i]}"
                fi
            done

            if [[ -n "$test_name" && -n "$index_val" ]]; then
                test_num=$((test_num + 1))
                result+="test${test_num}.name ${test_name}"$'\n'
                result+="test${test_num}.score ${score_val}"$'\n'
                result+="test${test_num}.index ${index_val}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
