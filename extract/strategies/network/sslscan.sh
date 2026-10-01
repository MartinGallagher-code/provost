#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: sslscan
## Description: Extract accepted/preferred cipher rows from sslscan output
## Version: 1.0
## Priority: 20
## Sample: samples/sslscan/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
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

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Cipher rows: "Preferred|Accepted  <proto>  <bits> bits  <cipher>"
        case "$line" in
            Preferred[[:space:]]*|Accepted[[:space:]]*) : ;;
            *) continue ;;
        esac

        { _fr_tok "$line"; _arr=("${_FR_TOK[@]}"); }
        # status proto bits "bits" cipher
        [[ ${#_arr[@]} -lt 5 ]] && continue

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}status ${_arr[0]}"$'\n'
        result+="${p}protocol ${_arr[1]}"$'\n'
        result+="${p}bits ${_arr[2]}"$'\n'
        result+="${p}cipher ${_arr[4]}"$'\n'
    done

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
