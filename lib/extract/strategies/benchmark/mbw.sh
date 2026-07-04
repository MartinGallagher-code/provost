#!/bin/bash
## Name: mbw
## Description: Extract memory bandwidth measurements from mbw output
## Version: 1.0
## Priority: 15
## Sample: samples/mbw/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    if [[ "$text" == *"MiB/s"* ]]; then
        if [[ "$text" == *"MEMCPY"* || "$text" == *"DUMB"* || "$text" == *"MCBLOCK"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract array size if present: "Long uses 8 bytes. ..."
    local array_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"array size"* ]]; then
            array_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$array_line" ]]; then
        local array_size="${array_line#*array size: }"
        # If pattern didn't match, try with spaces
        if [[ "$array_size" == "$array_line" ]]; then
            array_size="${array_line#*array size:}"
            while [[ "$array_size" == " "* ]]; do array_size="${array_size# }"; done
        fi
        array_size="${array_size// /_}"
        [[ -n "$array_size" ]] && result+="array_size ${array_size}"$'\n'
    fi

    # Parse result lines: "Method: MEMCPY	Elapsed: 0.12345	MiB: 256.000	Copy: 2076.543 MiB/s"
    # Also handles: "AVG	Method: MEMCPY	Elapsed: 0.12345	MiB: 256.000	Copy: 2076.543 MiB/s"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *"MiB/s"* ]] || continue

        local method elapsed copy_rate is_avg=""

        # Check if this is an AVG line
        if [[ "$line" == "AVG"* ]]; then
            is_avg="avg_"
        fi

        method=$(_strat_mbw_extract_value "$line" "Method:")
        elapsed=$(_strat_mbw_extract_value "$line" "Elapsed:")
        # Extract copy rate: everything after "Copy: " up to first space
        local copy_part="${line#*Copy: }"
        if [[ "$copy_part" == "$line" ]]; then
            copy_part="${line#*Copy:}"
            while [[ "$copy_part" == " "* || "$copy_part" == $'\t'* ]]; do copy_part="${copy_part#?}"; done
        fi
        read -ra _arr <<< "$copy_part"
        copy_rate="${_arr[0]}"

        [[ -z "$method" || -z "$copy_rate" ]] && continue

        # Normalize method name to lowercase
        local method_lower
        method_lower=$(echo "$method" | tr '[:upper:]' '[:lower:]')

        result+="${is_avg}${method_lower}.elapsed ${elapsed}"$'\n'
        result+="${is_avg}${method_lower}.throughput_MiB_per_s ${copy_rate}"$'\n'
    done <<< "$text"

    echo "$result"
}

_strat_mbw_extract_value () {
    local line="$1"
    local key="$2"
    # Extract value after key, up to first whitespace/tab
    [[ "$line" == *"$key"* ]] || return
    local after="${line#*"$key"}"
    while [[ "$after" == " "* || "$after" == $'\t'* ]]; do after="${after#?}"; done
    read -ra _arr <<< "$after"
    echo "${_arr[0]}"
}
