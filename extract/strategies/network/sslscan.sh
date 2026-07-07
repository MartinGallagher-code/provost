#!/bin/bash
## Name: sslscan
## Description: Extract accepted/preferred cipher rows from sslscan output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/sslscan/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1
    if [[ "$text" == *"Supported Server Cipher"* ]] \
       || { [[ "$text" == *"Accepted"* ]] && [[ "$text" == *"bits"* ]] && [[ "$text" == *"TLS"* ]]; }; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    while IFS= read -r line; do
        # Cipher rows: "Preferred|Accepted  <proto>  <bits> bits  <cipher>"
        case "$line" in
            Preferred[[:space:]]*|Accepted[[:space:]]*) : ;;
            *) continue ;;
        esac

        read -ra _arr <<< "$line"
        # status proto bits "bits" cipher
        [[ ${#_arr[@]} -lt 5 ]] && continue

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}status ${_arr[0]}"$'\n'
        result+="${p}protocol ${_arr[1]}"$'\n'
        result+="${p}bits ${_arr[2]}"$'\n'
        result+="${p}cipher ${_arr[4]}"$'\n'
    done <<< "$text"

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
