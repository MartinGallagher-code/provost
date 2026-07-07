#!/bin/bash
## Name: unzip
## Description: Extract file entries from `unzip -l` listings (skips banner/header + rule + totals footer)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/unzip/basic.txt

# `unzip -l` prints an "Archive:  <name>" banner, a "Length Date Time Name"
# column header, a dashed rule, one row per archived file, a second dashed rule,
# then a totals footer ("<total>  N files"). Only the rows between the two rules
# are data.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive unzip -l banner + header columns.
    [[ "$text" == *"Archive:"* && "$text" == *"Length"* && "$text" == *"Name"* ]] || return 1
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
        [[ ${#t[@]} -ge 4 ]] || continue
        local name="" i
        for ((i=3; i<${#t[@]}; i++)); do name+="${t[i]}_"; done
        name="${name%_}"
        entry=$((entry + 1))
        result+="entry${entry}.length ${t[0]}"$'\n'
        result+="entry${entry}.date ${t[1]}"$'\n'
        result+="entry${entry}.time ${t[2]}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
