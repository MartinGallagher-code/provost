#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: free
## Description: Extract memory and swap usage from free -h / free -m output
## Version: 2.0
## Priority: 10
## Sample: samples/free/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Reject JSON
    _is_json "$1" && return 1
    # Look for header with "total" and "used", followed by "Mem:" or "Swap:" line
    local has_header=0 has_mem_swap=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" == *"total"* && "$line" == *"used"* ]]; then
            has_header=1
        fi
        if [[ "$line" == "Mem:"* || "$line" == "Swap:"* ]]; then
            has_mem_swap=1
        fi
    done
    if [[ $has_header -eq 1 && $has_mem_swap -eq 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # `free` is already a table: a header of column names, then one row per
    # region (`Mem:`, `Swap:`, and `Total:` with `free -t`). Emit it as indexed
    # `entry<N>.<field>` groups — the same shape ls-l / kv-pairs use — so the
    # capture-side tidy melt turns it back into one row per region with shared
    # columns (name, total, used, free, shared, buff_cache, available) instead
    # of welding both regions into a single unintelligible wide record.
    local -a cols=()
    local header_seen=0
    local idx=0
    local line

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue

        # Header row: contains the column labels but no leading "Region:" tag.
        # (`buff/cache` is sanitised to `buff_cache` so it is a valid field name;
        # the older `buffers`/`cached` split header is carried through verbatim.)
        if [[ $header_seen -eq 0 && "$line" == *"total"* && "$line" == *"used"* && "$line" != *:* ]]; then
            { _fr_tok "$line"; _h=("${_FR_TOK[@]}"); }
            cols=()
            local c
            for c in "${_h[@]}"; do
                c="${c//\//_}"   # buff/cache -> buff_cache
                cols+=("$c")
            done
            header_seen=1
            continue
        fi

        # Data row: "Region:  v1 v2 v3 ...". The label before ':' names the row.
        if [[ "$line" == *:* ]]; then
            local label="${line%%:*}"
            label="${label// /}"
            [[ -z "$label" ]] && continue
            local after="${line#*:}"
            { _fr_tok "$after"; _v=("${_FR_TOK[@]}"); }
            [[ ${#_v[@]} -eq 0 ]] && continue

            idx=$((idx + 1))
            result+="entry${idx}.name ${label}"$'\n'
            local i col
            for i in "${!_v[@]}"; do
                col="${cols[$i]:-col$((i + 1))}"
                result+="entry${idx}.${col} ${_v[$i]}"$'\n'
            done
            continue
        fi
    done

    [[ $idx -gt 0 ]] && result+="total_entries ${idx}"$'\n'
    echo "$result"
}
