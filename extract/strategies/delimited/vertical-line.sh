#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: vertical-line
## Description: Extract data from tables with separator lines (---, ===, etc.)
## Version: 1.0
## Priority: 45
## Sample: samples/vertical-line/benchmark.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=70
    # Apply if input contains a separator line (--- or === repeated)
    [[ "$text" =~ (^|$'\n')[-=]{3,} ]] || return 1

    # Decline a `label: value` key/value block that merely carries a `===`/`---`
    # banner (aureport --summary, `duplicity collection-status`). vertical-line
    # would split the banner's title line into positional columns and shred the
    # values; the `colons` parser tidies these to one field per label. Examine the
    # lines below the FIRST separator (the data region) — if most are `label: value`,
    # defer.
    local seen_sep=0 nb=0 kv=0 _l
    while IFS= read -r _l; do
        if [[ $seen_sep -eq 0 ]]; then
            [[ "$_l" =~ ^[-=]{3,} ]] && seen_sep=1
            continue
        fi
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        [[ "$_l" =~ ^[[:space:]]*[A-Za-z][^:]*:[[:space:]] ]] && kv=$((kv + 1))
    done <<< "$text"
    [[ $nb -ge 2 && $(( kv * 100 / nb )) -ge 60 ]] && return 1

    # Audit-report shape (aureport): a `# col col …` header line adjacent to
    # a `===` rule. aligned-columns strips that chrome and reads the real
    # header; splitting on the rule here would shred it.
    local _prev="" _cur
    while IFS= read -r _cur; do
        if [[ "$_cur" == "# "* && "$_prev" =~ ^[-=]{3,} ]] || \
           [[ "$_cur" =~ ^[-=]{3,} && "$_prev" == "# "* ]]; then
            return 1
        fi
        _prev="$_cur"
    done <<< "$text"
    return 0
}

strategy_extract () {
    local text="$1"

    # Find the separator line number
    local separator_line_num=0
    local _line_num=0
    while IFS= read -r _line; do
        _line_num=$((_line_num + 1))
        if [[ "$_line" =~ ^[-=]{3,} ]]; then
            separator_line_num=$_line_num
            break
        fi
    done <<< "$text"
    [[ $separator_line_num -eq 0 ]] && return

    # Header is the line before the separator
    local header_num=$((separator_line_num - 1))
    [[ $header_num -lt 1 ]] && return

    local header_line=""
    _line_num=0
    while IFS= read -r _line; do
        _line_num=$((_line_num + 1))
        if [[ $_line_num -eq $header_num ]]; then
            header_line="$_line"
            break
        fi
    done <<< "$text"
    [[ -z "$header_line" ]] && return

    # Find header word positions (start and end of each word)
    local h_starts; h_starts=()
    local h_ends; h_ends=()
    local in_word=0
    local i
    for ((i=0; i<${#header_line}; i++)); do
        local ch="${header_line:$i:1}"
        if [[ "$ch" != " " ]]; then
            if [[ $in_word -eq 0 ]]; then
                h_starts+=("$i")
                in_word=1
            fi
        else
            if [[ $in_word -eq 1 ]]; then
                h_ends+=($((i-1)))
                in_word=0
            fi
        fi
    done
    [[ $in_word -eq 1 ]] && h_ends+=($((${#header_line}-1)))

    local num_cols=${#h_starts[@]}
    [[ $num_cols -lt 1 ]] && return

    # Extract column names from header
    local col_names; col_names=()
    local c
    for ((c=0; c<num_cols; c++)); do
        local start=${h_starts[$c]}
        local end=${h_ends[$c]}
        col_names+=("${header_line:$start:$((end-start+1))}")
    done

    # Compute column boundaries using midpoints of inter-header gaps.
    # This correctly handles right-aligned data that extends beyond header text.
    local col_lo; col_lo=()
    local col_hi; col_hi=()
    col_lo=(0)
    for ((c=1; c<num_cols; c++)); do
        local prev_end=${h_ends[$((c-1))]}
        local this_start=${h_starts[$c]}
        local boundary=$(( (prev_end + this_start + 1) / 2 ))
        col_hi+=("$boundary")
        col_lo+=("$boundary")
    done
    col_hi+=(99999)

    # Get data lines (everything after the separator, skip blank lines)
    local data_lines=""
    _line_num=0
    while IFS= read -r _line; do
        _line_num=$((_line_num + 1))
        [[ $_line_num -le $separator_line_num ]] && continue
        [[ -z "$_line" ]] && continue
        if [[ -z "$data_lines" ]]; then
            data_lines="$_line"
        else
            data_lines+=$'\n'"$_line"
        fi
    done <<< "$text"
    [[ -z "$data_lines" ]] && return

    # For each data row, extract values using computed column boundaries and emit
    # an indexed record group (entry<N>.<column>) so the tidy melt renders one row
    # per data line instead of welding every cell into one wide record.
    local result=""
    local entry=0
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        entry=$((entry + 1))

        for ((c=0; c<num_cols; c++)); do
            local lo=${col_lo[$c]}
            local hi=${col_hi[$c]}

            # Clamp to row length
            [[ $lo -ge ${#row} ]] && continue
            local len=$((hi - lo))
            [[ $((lo + len)) -gt ${#row} ]] && len=$((${#row} - lo))

            local value="${row:$lo:$len}"
            # Trim surrounding whitespace; internal spaces are part of the value.
            while [[ "$value" == " "* ]]; do value="${value# }"; done
            while [[ "$value" == *" " ]]; do value="${value% }"; done
            [[ -z "$value" ]] && continue

            local name="${col_names[$c]}"
            name="${name//./_}"   # '.' would break the tidy melt's group key split
            result+="entry${entry}.${name} ${value}"$'\n'
        done
    done <<< "$data_lines"

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
