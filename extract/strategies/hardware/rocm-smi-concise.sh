#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: rocm-smi-concise
## Description: Extract the GPU concise-info table from rocm-smi (skips banners)
## Version: 1.0
## Priority: 8
## Sample: samples/rocm-smi-concise/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1
    if [[ "$text" == *"ROCm System Management Interface"* ]] \
       || { [[ "$text" == *"AvgPwr"* ]] && [[ "$text" == *"SCLK"* ]] && [[ "$text" == *"PwrCap"* ]]; }; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip banner/rule lines and the column header.
        case "$line" in
            *=*) continue ;;
            GPU[[:space:]]*) continue ;;
        esac
        # Data rows begin with the GPU index (a number).
        [[ "$line" =~ ^[0-9] ]] || continue

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 10 ]] && continue

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}gpu ${_arr[0]}"$'\n'
        result+="${p}temp ${_arr[1]}"$'\n'
        result+="${p}avgpwr ${_arr[2]}"$'\n'
        result+="${p}sclk ${_arr[3]}"$'\n'
        result+="${p}mclk ${_arr[4]}"$'\n'
        result+="${p}fan ${_arr[5]}"$'\n'
        result+="${p}perf ${_arr[6]}"$'\n'
        result+="${p}pwrcap ${_arr[7]}"$'\n'
        result+="${p}vram_pct ${_arr[8]}"$'\n'
        result+="${p}gpu_pct ${_arr[9]}"$'\n'
    done <<< "$text"

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
