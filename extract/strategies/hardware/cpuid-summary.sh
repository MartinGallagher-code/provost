#!/bin/bash
## Name: cpuid-summary
## Description: `cpuid` decoded summary ("key = value (n)" register fields)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/cpuid-summary/basic.txt

# `cpuid` (decoded/summary form) prints indented "key = value" lines grouped
# under register section headers ("version information (1/eax):"). Generic
# key/value parsers choke on the parenthesised sections and the aligned "=".
# This lifts every "key = value" line into one wide record.

_cpuid_key () {
    local s="$1" out="" c i n=${#1}
    for ((i = 0; i < n; i++)); do
        c="${s:i:1}"
        case "$c" in
            [A-Za-z0-9]) out+="$c" ;;
            *) out+="_" ;;
        esac
    done
    while [[ "$out" == *__* ]]; do out="${out//__/_}"; done
    out="${out#_}"; out="${out%_}"
    printf '%s' "$out"
}

_cpuid_val () {
    local v="$1"
    v="${v//$'\t'/ }"
    while [[ "$v" == *"  "* ]]; do v="${v//  / }"; done
    v="${v# }"; v="${v% }"
    # Strip surrounding double quotes from string values.
    v="${v#\"}"; v="${v%\"}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Distinctive: a "vendor_id =" line and a decoded register section such as
    # "(1/eax)" — both hallmarks of cpuid summary output.
    [[ "$text" == *"vendor_id ="* ]] || return 1
    [[ "$text" == *"(1/eax)"* || "$text" == *"version information"* ]] || return 1

    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line key val

    while IFS= read -r line; do
        [[ "$line" == *" = "* ]] || continue
        key="${line%% = *}"
        val="${line#* = }"
        key="$(_cpuid_key "$key")"
        [[ -z "$key" ]] && continue
        val="$(_cpuid_val "$val")"
        result+="entry1.${key} ${val}"$'\n'
    done <<< "$text"

    result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
