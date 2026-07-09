#!/bin/bash
## Name: 7z
## Description: Extract file entries from `7z l` archive listings (skips header rule + totals footer)
## Version: 1.0
## Priority: 22
## Sample: samples/7z/basic.txt

# `7z l` prints a column header ("Date Time Attr Size Compressed Name"), a
# dashed rule, one row per archived file, a second dashed rule, then a totals
# footer ("<date> <time>  <size> <comp>  N files"). Only the rows between the two
# rules are data — the header, rules, and footer are skipped so the count is
# exact.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive 7z listing header: Attr + Compressed + Name columns.
    [[ "$text" == *"Attr"* && "$text" == *"Compressed"* && "$text" == *"Name"* ]] || return 1
    # Must have a dashed rule line.
    local line stripped
    while IFS= read -r line; do
        stripped="${line//[- ]/}"
        if [[ -z "$stripped" && "$line" == *-* ]]; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 in_data=0 line stripped
    local -a t
    while IFS= read -r line; do
        stripped="${line//[- ]/}"
        if [[ -z "$stripped" && "$line" == *-* ]]; then
            if [[ $in_data -eq 0 ]]; then in_data=1; else in_data=0; fi
            continue
        fi
        [[ $in_data -eq 1 ]] || continue
        [[ -z "$line" ]] && continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -ge 6 ]] || continue
        local name="" i
        for ((i=5; i<${#t[@]}; i++)); do name+="${t[i]}_"; done
        name="${name%_}"
        entry=$((entry + 1))
        result+="entry${entry}.date ${t[0]}"$'\n'
        result+="entry${entry}.time ${t[1]}"$'\n'
        result+="entry${entry}.attr ${t[2]}"$'\n'
        result+="entry${entry}.size ${t[3]}"$'\n'
        result+="entry${entry}.compressed ${t[4]}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
