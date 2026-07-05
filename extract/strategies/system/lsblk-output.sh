#!/bin/bash
## Name: lsblk-output
## Description: Extract filesystem info from lsblk -f output with FSTYPE and LABEL columns
## Version: 1.0
## Priority: 40
## Technique: table
## Sample: samples/lsblk-output/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
    _is_json "$text" && return 1
    # lsblk -f has NAME FSTYPE FSVER LABEL UUID FSAVAIL FSUSE% MOUNTPOINTS
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    if [[ "$first_line" == *"NAME"* && "$first_line" == *"FSTYPE"* && "$first_line" == *"UUID"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local dev_n=0
    local past_header=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == *"NAME"* && "$line" == *"FSTYPE"* && "$line" == *"UUID"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        # Strip tree drawing characters - keep only alphanumeric content
        local stripped=""
        local found_start=0
        local pos=0
        while [[ $pos -lt ${#line} ]]; do
            local ch="${line:$pos:1}"
            if [[ $found_start -eq 0 ]]; then
                case "$ch" in
                    [a-zA-Z0-9]) found_start=1; stripped+="$ch" ;;
                esac
            else
                stripped+="$ch"
            fi
            pos=$((pos + 1))
        done

        [[ -z "$stripped" ]] && continue
        read -ra _arr <<< "$stripped"
        [[ ${#_arr[@]} -lt 1 ]] && continue

        dev_n=$((dev_n + 1))
        local prefix="dev${dev_n}"

        local dev_name="${_arr[0]}"
        result+="${prefix}.name ${dev_name}"$'\n'

        # FSTYPE is at index 1 if present
        if [[ ${#_arr[@]} -ge 2 && -n "${_arr[1]}" ]]; then
            result+="${prefix}.fstype ${_arr[1]}"$'\n'
        fi

        # Look for UUID pattern (8-4-4-4-12 hex)
        local i
        for ((i=1; i<${#_arr[@]}; i++)); do
            case "${_arr[$i]}" in
                [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-*)
                    result+="${prefix}.uuid ${_arr[$i]}"$'\n'
                    ;;
            esac
            # Detect mountpoint (starts with /)
            case "${_arr[$i]}" in
                /*)
                    result+="${prefix}.mountpoint ${_arr[$i]}"$'\n'
                    ;;
            esac
            # Detect percentage
            case "${_arr[$i]}" in
                *%)
                    result+="${prefix}.usage ${_arr[$i]}"$'\n'
                    ;;
            esac
        done
    done <<< "$text"

    echo "$result"
}
