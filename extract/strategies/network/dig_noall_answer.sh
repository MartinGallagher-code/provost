#!/bin/bash
## Name: dig_noall_answer
## Description: Extract DNS answer records from `dig +noall +answer` output
## Version: 1.0
## Priority: 8
## Technique: yes
## Sample: samples/dig_noall_answer/basic.txt

# `dig +noall +answer <name>` prints ONLY the answer rows, with no headers,
# comments or section markers at all:
#   example.com.   86400   IN   A   93.184.216.34
# Every non-blank line is an answer row of the shape `name TTL IN TYPE value`
# (tab- or space-separated). Detection requires that EVERY non-blank line looks
# like an answer row (no `;` comments, no other markers) so it stays specific.

_dig_is_answer_row () {
    # $1 = whitespace-split field count sentinel; args are the fields.
    local n="$1"; shift
    [[ $n -ge 5 && "$2" == "IN" && "$1" =~ ^[0-9]+$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line seen=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == ";"* ]] && return 1
        local -a f=()
        read -ra f <<< "$line"
        # fields: name TTL IN TYPE value...  -> f[1]=TTL f[2]=IN
        if [[ ${#f[@]} -ge 5 && "${f[2]}" == "IN" && "${f[1]}" =~ ^[0-9]+$ ]]; then
            seen=1
        else
            return 1
        fi
    done <<< "$text"
    [[ $seen -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == ";"* ]] && continue
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
