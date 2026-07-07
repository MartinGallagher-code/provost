#!/bin/bash
## Name: dig_any
## Description: Extract DNS answer records from `dig ANY` output
## Version: 1.0
## Priority: 8
## Technique: yes
## Sample: samples/dig_any/basic.txt

# `dig ANY <name>` prints a full dig report; the ANSWER SECTION carries mixed
# record types (A, AAAA, MX, NS, TXT, ...):
#   example.com.   86400   IN   A   93.184.216.34
# We emit one record per answer row of the shape `name TTL IN TYPE value`.
# All `;`-comment lines (banner, options, HEADER, QUESTION), section markers and
# blanks are skipped. Detection keys on the dig banner naming an ANY query.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line banner=0 answer=0
    while IFS= read -r line; do
        [[ "$line" == *"<<>>"*"ANY"* ]] && banner=1
        [[ -z "$line" || "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 5 && "${f[2]}" == "IN" && "${f[1]}" =~ ^[0-9]+$ ]] && answer=1
    done <<< "$text"
    [[ $banner -eq 1 && $answer -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 5 && "${f[2]}" == "IN" && "${f[1]}" =~ ^[0-9]+$ ]] || continue
        local val="" i
        for ((i=4; i<${#f[@]}; i++)); do
            if [[ -z "$val" ]]; then val="${f[$i]}"; else val="${val}_${f[$i]}"; fi
        done
        val="${val// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${f[0]}"$'\n'
        result+="entry${entry}.ttl ${f[1]}"$'\n'
        result+="entry${entry}.class ${f[2]}"$'\n'
        result+="entry${entry}.type ${f[3]}"$'\n'
        result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
