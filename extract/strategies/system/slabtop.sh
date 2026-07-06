#!/bin/bash
## Name: slabtop
## Description: Extract per-cache records from slabtop output (objs, active, use, sizes, name)
## Version: 1.0
## Priority: 20
## Sample: samples/slabtop/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: slabtop's cache table header.
    if [[ "$text" == *"OBJS"*"ACTIVE"*"OBJ SIZE"*"NAME"* ]] \
       || [[ "$text" == *"Active / Total Objects"* ]]; then
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

        # The OBJS/ACTIVE header marks the start of the cache table.
        if [[ "$line" == *"OBJS"* ]] && [[ "$line" == *"ACTIVE"* ]] && [[ "$line" == *"NAME"* ]]; then
            in_table=1
            continue
        fi
        [[ $in_table -eq 0 ]] && continue

        local v
        read -ra v <<< "$line"
        [[ ${#v[@]} -lt 8 ]] && continue
        # data rows start with a numeric OBJS count
        [[ "${v[0]}" =~ ^[0-9]+$ ]] || continue

        entry=$((entry + 1))
        result+="entry${entry}.objs ${v[0]}"$'\n'
        result+="entry${entry}.active ${v[1]}"$'\n'
        result+="entry${entry}.use ${v[2]}"$'\n'
        result+="entry${entry}.obj_size ${v[3]}"$'\n'
        result+="entry${entry}.slabs ${v[4]}"$'\n'
        result+="entry${entry}.obj_per_slab ${v[5]}"$'\n'
        result+="entry${entry}.cache_size ${v[6]}"$'\n'
        result+="entry${entry}.name ${v[7]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
