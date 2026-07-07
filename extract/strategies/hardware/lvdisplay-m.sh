#!/bin/bash
## Name: lvdisplay-m
## Description: Extract the Logical volume key/value block from lvdisplay -m (one wide record)
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/lvdisplay-m/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1
    # lvdisplay -m: a "--- Logical volume ---" banner with LV Path / LV Name keys.
    if [[ "$text" == *"--- Logical volume ---"* ]] && [[ "$text" == *"LV Path"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_lv=0

    while IFS= read -r line; do
        # Only parse the Logical volume block; stop at the Segments section.
        case "$line" in
            *"--- Logical volume ---"*) in_lv=1; continue ;;
            *"--- Segments ---"*) in_lv=0; continue ;;
            *"---"*) in_lv=0; continue ;;
        esac
        [[ $in_lv -eq 1 ]] || continue
        [[ -z "$line" ]] && continue

        # Trim leading whitespace.
        local t="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$t" ]] && continue

        # Split on the first run of 2+ spaces: left = key, right = value.
        local key val
        if [[ "$t" =~ ^(.*[^[:space:]])[[:space:]][[:space:]]+(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
        else
            key="$t"
            val=""
        fi
        [[ -z "$key" ]] && continue

        # Sanitise spaces to underscores in both key and value.
        key="${key// /_}"
        val="${val// /_}"
        result+="entry1.${key} ${val}"$'\n'
    done <<< "$text"

    result+="total_entries 1"$'\n'
    echo "$result"
}
