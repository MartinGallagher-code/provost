#!/bin/bash
## Name: aligned-columns
## Description: Extract fields from whitespace-aligned columnar output (ps, df, mount, etc.)
## Version: 2.0
## Priority: 70
## Technique: yes
## Sample: samples/aligned-columns/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=30

    # Apply if input has a header-like first line and consistent column structure
    # Must have at least 2 lines and 2+ words in the first line
    local line_count=0
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        line_count=$((line_count + 1))
        if [[ $line_count -eq 1 ]]; then
            first_line="$_line"
        fi
        [[ $line_count -ge 2 ]] && break
    done <<< "$text"
    [[ $line_count -lt 2 ]] && return 1

    read -ra _arr <<< "$first_line"
    local word_count=${#_arr[@]}
    [[ $word_count -lt 2 ]] && return 1

    # Check that header words are all uppercase or capitalized (heuristic)
    # This helps distinguish column headers from regular text
    if [[ "$first_line" =~ ^[A-Z%][A-Z%a-z0-9_\ -]*[A-Z%][A-Z%a-z0-9_\ -]*$ ]]; then
        return 0
    fi

    # Also detect if there's a separator line (handled by vertical-line strategy primarily,
    # but aligned-columns works without separators too)
    return 1
}

strategy_extract () {
    local text="$1"

    # Skip blank lines at the start — collect non-empty lines
    local _cleaned=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _cleaned+="$_line"$'\n'
    done <<< "$text"
    text="$_cleaned"

    local header=""
    local _first=1
    while IFS= read -r _line; do
        if [[ $_first -eq 1 ]]; then
            header="$_line"
            _first=0
            break
        fi
    done <<< "$text"

    # Normalize header whitespace using read
    local headers; headers=()
    read -ra headers <<< "$header"
    # Field names must not contain '.' (the tidy melt splits the group key on the
    # first dot: entry<N>.<field>).
    local _hi
    for ((_hi=0; _hi<${#headers[@]}; _hi++)); do
        headers[$_hi]="${headers[$_hi]//./_}"
    done

    # Emit each data line as an indexed row group (entry<N>.<field>) so the
    # capture-side tidy melt renders one row per line with shared columns,
    # rather than welding every row into a single wide record with duplicate
    # header keys (which is what a flat `<header> <value>` emission produced).
    local result=""
    local row_num=0
    local entry=0
    while IFS= read -r line; do
        row_num=$((row_num + 1))
        [[ $row_num -eq 1 ]] && continue  # skip header
        [[ -z "$line" ]] && continue

        # Normalize whitespace using read
        local values; values=()
        read -ra values <<< "$line"

        entry=$((entry + 1))
        local i
        for ((i=0; i<${#headers[@]}; i++)); do
            local name="${headers[$i]}"
            local value="${values[$i]:-}"
            [[ -z "$value" ]] && continue
            # If this is the last header and there are extra values, combine them
            if [[ $i -eq $((${#headers[@]} - 1)) && ${#values[@]} -gt ${#headers[@]} ]]; then
                local j
                for ((j=i+1; j<${#values[@]}; j++)); do
                    value+="_${values[$j]}"
                done
            fi
            result+="entry${entry}.${name} ${value}"$'\n'
        done
    done <<< "$text"

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
