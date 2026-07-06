#!/bin/bash
## Name: nethogs
## Description: Extract per-process records from nethogs output (pid, user, program, dev, sent, received)
## Version: 1.0
## Priority: 20
## Sample: samples/nethogs/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: the NetHogs banner plus its process header.
    if [[ "$text" == *"NetHogs"* ]] \
       && [[ "$text" == *"PROGRAM"* ]] \
       && [[ "$text" == *"SENT"* ]] \
       && [[ "$text" == *"RECEIVED"* ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local in_table=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == *"NetHogs version"* ]] && continue

        # The PID/USER/PROGRAM row is the header.
        if [[ "$line" == *"PID"* ]] && [[ "$line" == *"PROGRAM"* ]] && [[ "$line" == *"SENT"* ]]; then
            in_table=1
            continue
        fi
        [[ $in_table -eq 0 ]] && continue

        local v
        read -ra v <<< "$line"
        [[ ${#v[@]} -lt 6 ]] && continue
        [[ "${v[0]}" =~ ^[0-9]+$ ]] || continue

        # Columns: PID USER PROGRAM DEV SENT RECEIVED [unit]
        local unit="${v[6]:-}"

        entry=$((entry + 1))
        result+="entry${entry}.pid ${v[0]}"$'\n'
        result+="entry${entry}.user ${v[1]}"$'\n'
        result+="entry${entry}.program ${v[2]}"$'\n'
        result+="entry${entry}.dev ${v[3]}"$'\n'
        result+="entry${entry}.sent ${v[4]}"$'\n'
        result+="entry${entry}.received ${v[5]}"$'\n'
        [[ -n "$unit" ]] && result+="entry${entry}.unit ${unit}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
