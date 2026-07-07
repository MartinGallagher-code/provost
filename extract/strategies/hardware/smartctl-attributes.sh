#!/bin/bash
## Name: smartctl-attributes
## Description: Extract the SMART attributes table from smartctl -A output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/smartctl-attributes/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1
    if [[ "$text" == *"ATTRIBUTE_NAME"* ]] && [[ "$text" == *"RAW_VALUE"* ]] && [[ "$text" == *"WHEN_FAILED"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local past_header=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" == *"ATTRIBUTE_NAME"* && "$line" == *"RAW_VALUE"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 1 ]] || continue

        read -ra _arr <<< "$line"
        # ID# NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE
        [[ ${#_arr[@]} -lt 10 ]] && continue
        [[ "${_arr[0]}" =~ ^[0-9]+$ ]] || continue

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}id ${_arr[0]}"$'\n'
        result+="${p}attribute_name ${_arr[1]}"$'\n'
        result+="${p}flag ${_arr[2]}"$'\n'
        result+="${p}value ${_arr[3]}"$'\n'
        result+="${p}worst ${_arr[4]}"$'\n'
        result+="${p}thresh ${_arr[5]}"$'\n'
        result+="${p}type ${_arr[6]}"$'\n'
        result+="${p}updated ${_arr[7]}"$'\n'
        result+="${p}when_failed ${_arr[8]}"$'\n'
        result+="${p}raw_value ${_arr[9]}"$'\n'
    done <<< "$text"

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
