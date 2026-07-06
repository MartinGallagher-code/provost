#!/bin/bash
## Name: turbostat
## Description: Extract per-CPU records from turbostat output (columns from the header)
## Version: 1.0
## Priority: 20
## Sample: samples/turbostat/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: turbostat's per-CPU header carries Bzy_MHz and
    # Busy% alongside the Core/CPU columns.
    if [[ "$text" == *"Bzy_MHz"* ]] \
       && [[ "$text" == *"Busy%"* ]] \
       && [[ "$text" == *"Core"* ]] \
       && [[ "$text" == *"CPU"* ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local header=""
    local cols
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue

        # First Core/... line is the header; capture and normalize column names.
        if [[ -z "$header" ]] && [[ "$line" == *"Core"* ]] && [[ "$line" == *"Bzy_MHz"* ]]; then
            header="$line"
            read -ra cols <<< "$header"
            local i
            for ((i=0; i<${#cols[@]}; i++)); do
                cols[$i]=$(_strat_turbostat_norm "${cols[$i]}")
            done
            continue
        fi
        [[ -z "$header" ]] && continue

        local vals
        read -ra vals <<< "$line"
        [[ ${#vals[@]} -eq 0 ]] && continue

        # Skip the leading "-  -" package-aggregate summary row.
        [[ "${vals[0]}" == "-" ]] && continue

        entry=$((entry + 1))
        local j
        for ((j=0; j<${#cols[@]} && j<${#vals[@]}; j++)); do
            local name="${cols[$j]}"
            [[ -z "$name" ]] && continue
            result+="entry${entry}.${name} ${vals[$j]}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}

# Normalize a turbostat column name to letters/digits/underscore.
#   Busy%  -> Busy_pct   Avg_MHz -> Avg_MHz
_strat_turbostat_norm () {
    local c="$1"
    c="${c//%/_pct}"
    c="${c//[^A-Za-z0-9_]/_}"
    echo "$c"
}
