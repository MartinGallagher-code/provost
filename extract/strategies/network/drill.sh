#!/bin/bash
## Name: drill
## Description: Extract DNS answer/authority records from `drill` output
## Version: 1.0
## Priority: 8
## Sample: samples/drill/basic.txt

# `drill <name>` (ldns) prints a dig-like report. Its ANSWER and AUTHORITY
# sections both carry rows of the shape `name TTL IN TYPE value`:
#   example.com.   3600    IN   A    93.184.216.34
#   example.com.   86400   IN   NS   a.iana-servers.net.
# We emit one record per such row (section markers are `;;`-comments and are
# skipped, so both sections flow through). Detection keys on drill's HEADER line
# which uses `rcode:` (dig uses `status:`).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line banner=0 answer=0
    while IFS= read -r line; do
        [[ "$line" == *"->>HEADER<<-"*"rcode:"* ]] && banner=1
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
