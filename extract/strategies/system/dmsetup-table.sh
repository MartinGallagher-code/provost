#!/bin/bash
## Name: dmsetup-table
## Description: Extract device-mapper table rows from dmsetup table output
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/dmsetup-table/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1
    # dmsetup table: "<name>: <start> <len> <type> <params>" — name, colon, two
    # integers, then a device-mapper TARGET TYPE (an alphabetic keyword like
    # linear/striped/crypt/thin/cache/mirror/raid…). The alphabetic 4th field is
    # what distinguishes it from /proc/net/snmp value rows ("Ip: 1 64 0 …", all
    # numeric).
    local hits=0
    while IFS= read -r _line; do
        [[ "$_line" =~ ^[^[:space:]:]+:[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[a-zA-Z] ]] && hits=$((hits + 1))
    done <<< "$text"
    [[ $hits -ge 2 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    while IFS= read -r line; do
        [[ "$line" =~ ^([^[:space:]:]+):[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([^[:space:]]+)[[:space:]]*(.*)$ ]] || continue
        local name="${BASH_REMATCH[1]}"
        local start="${BASH_REMATCH[2]}"
        local len="${BASH_REMATCH[3]}"
        local type="${BASH_REMATCH[4]}"
        local params="${BASH_REMATCH[5]}"

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}name ${name}"$'\n'
        result+="${p}start ${start}"$'\n'
        result+="${p}len ${len}"$'\n'
        result+="${p}type ${type}"$'\n'
        result+="${p}params ${params// /_}"$'\n'
    done <<< "$text"

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
