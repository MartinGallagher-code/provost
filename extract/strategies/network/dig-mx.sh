#!/bin/bash
## Name: dig-mx
## Description: Extract MX answer records from `dig MX` output
## Version: 1.0
## Priority: 9
## Sample: samples/dig-mx/basic.txt

# `dig MX <name>` prints one answer per line in the ANSWER SECTION:
#   example.com.        3600    IN      MX      10 mail1.example.com.
# Fields are name TTL class(IN) type(MX) preference exchange. Comment lines
# begin with ';' (headers, options, the QUESTION SECTION) and are skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line
    while IFS= read -r line; do
        [[ "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 6 && "${f[2]}" == "IN" && "${f[3]}" == "MX" ]] && return 0
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 6 && "${f[2]}" == "IN" && "${f[3]}" == "MX" ]] || continue
        entry=$((entry + 1))
        local exch="${f[5]}"
        result+="entry${entry}.name ${f[0]}"$'\n'
        result+="entry${entry}.ttl ${f[1]}"$'\n'
        result+="entry${entry}.class ${f[2]}"$'\n'
        result+="entry${entry}.type ${f[3]}"$'\n'
        result+="entry${entry}.preference ${f[4]}"$'\n'
        result+="entry${entry}.exchange ${exch}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
