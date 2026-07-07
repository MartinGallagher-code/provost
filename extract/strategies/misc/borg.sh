#!/bin/bash
## Name: borg
## Description: Extract archives from `borg list` output (name, timestamp, archive id)
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/borg/basic.txt

# `borg list` prints one archive per line: "<name>   <Weekday>, <date> <time>
# [<hex-id>]". Every line is data — each becomes a record with the archive name,
# weekday, date, time, and id.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Signature: line ending in a bracketed hex id, with a weekday+date field.
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ [A-Za-z]+,[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}.*\[[0-9a-f]+\][[:space:]]*$ ]]; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a t
    while IFS= read -r line; do
        [[ "$line" =~ [A-Za-z]+,[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}.*\[[0-9a-f]+\][[:space:]]*$ ]] || continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -ge 5 ]] || continue
        local id="${t[4]}"; id="${id#[}"; id="${id%]}"
        local weekday="${t[1]}"; weekday="${weekday%,}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${t[0]}"$'\n'
        result+="entry${entry}.weekday ${weekday}"$'\n'
        result+="entry${entry}.date ${t[2]}"$'\n'
        result+="entry${entry}.time ${t[3]}"$'\n'
        result+="entry${entry}.id ${id}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
