#!/bin/bash
## Name: stream
## Description: Extract memory bandwidth rates from STREAM benchmark output
## Version: 1.0
## Priority: 10
## Sample: samples/stream/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    # STREAM banner: "STREAM version $Revision: ..."
    if [[ "$text" == *[Ss][Tt][Rr][Ee][Aa][Mm]" "[Vv]ersion* ]]; then
        return 0
    fi
    # Results table header: "Function    Best Rate MB/s  Avg time  Min time  Max time"
    if [[ "$text" == *"Best Rate"* ]] && \
       [[ "$text" == *"Copy"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract array size: "Array size = 10000000 (elements)"
    local array_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Array size"* ]]; then
            array_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$array_line" ]]; then
        local _after="${array_line#*Array size = }"
        while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
        read -ra _arr <<< "$_after"
        local array_size="${_arr[0]}"
        [[ -n "$array_size" ]] && result+="array_size ${array_size}"$'\n'
    fi

    # Extract total memory: "Total memory required = ... MiB"
    local mem_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Total memory"* ]]; then
            mem_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$mem_line" ]]; then
        local _after="${mem_line#*= }"
        while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
        # Remove parentheses and periods, replace spaces with underscores
        _after="${_after//(/}"
        _after="${_after//)/}"
        _after="${_after//./}"
        _after="${_after// /_}"
        # Strip trailing underscore
        while [[ "$_after" == *"_" ]]; do _after="${_after%_}"; done
        [[ -n "$_after" ]] && result+="total_memory ${_after}"$'\n'
    fi

    # Extract number of threads if present: "Number of Threads requested = 4"
    local thread_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Number of Threads"* ]]; then
            thread_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$thread_line" ]]; then
        local _after="${thread_line#*= }"
        while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
        read -ra _arr <<< "$_after"
        local num_threads="${_arr[0]}"
        [[ -n "$num_threads" ]] && result+="num_threads ${num_threads}"$'\n'
    fi

    # Parse results table:
    # Function    Best Rate MB/s  Avg time     Min time     Max time
    # Copy:      25000.0         0.006400     0.006400     0.006400
    # Scale:     24500.0         0.006531     0.006531     0.006531
    # Add:       27000.0         0.008889     0.008889     0.008889
    # Triad:     26800.0         0.008955     0.008955     0.008955
    local in_table=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect table start
        if [[ "$line" == *"Best Rate"* ]]; then
            in_table=1
            continue
        fi

        [[ $in_table -eq 0 ]] && continue

        # Skip separator lines
        [[ "$line" == -* ]] && continue

        # Parse data row: "Copy:      25000.0         0.006400 ..."
        read -ra _arr <<< "$line"
        local func_name="${_arr[0]}"
        func_name="${func_name%:}"
        local rate="${_arr[1]}"
        local avg_time="${_arr[2]}"
        local min_time="${_arr[3]}"
        local max_time="${_arr[4]}"

        # Validate: function name should be Copy/Scale/Add/Triad
        case "$func_name" in
            Copy|Scale|Add|Triad) ;;
            *) continue ;;
        esac

        # Validate: rate should be numeric
        [[ "$rate" =~ ^[0-9] ]] || continue

        local func_lower
        case "$func_name" in
            Copy)  func_lower="copy" ;;
            Scale) func_lower="scale" ;;
            Add)   func_lower="add" ;;
            Triad) func_lower="triad" ;;
        esac

        result+="${func_lower}.best_rate_MB_per_s ${rate}"$'\n'
        [[ -n "$avg_time" ]] && result+="${func_lower}.avg_time ${avg_time}"$'\n'
        [[ -n "$min_time" ]] && result+="${func_lower}.min_time ${min_time}"$'\n'
        [[ -n "$max_time" ]] && result+="${func_lower}.max_time ${max_time}"$'\n'
    done <<< "$text"

    echo "$result"
}
