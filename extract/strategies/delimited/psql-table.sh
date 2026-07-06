#!/bin/bash
## Name: psql-table
## Description: Pipe-delimited box tables with a ---+--- separator (psql, mysql \G-less output)
## Version: 1.0
## Priority: 35
## Technique: yes
## Sample: samples/psql-table/basic.txt

# Is a line a box-table separator? Only '-', '+', and spaces, with at least one
# '+' joint and a run of dashes -- e.g. "----+----+----" or "+----+----+".
_psql_is_separator () {
    local l="$1"
    [[ "$l" == *"+"* ]] || return 1
    [[ "$l" =~ ^[-+\ ]+$ ]] || return 1
    [[ "$l" == *"---"* ]] || return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Walk lines keeping the previous line so we can confirm the row above the
    # separator carries a '|' column delimiter, and that at least one row below
    # does too. Only then is this a genuine pipe box table.
    local _prev="" _line _sep_hdr="" _saw_data=0 _hit_sep=0
    while IFS= read -r _line; do
        if [[ $_hit_sep -eq 0 ]]; then
            if _psql_is_separator "$_line"; then
                [[ "$_prev" == *"|"* ]] || { _prev="$_line"; continue; }
                _hit_sep=1
            fi
        else
            [[ "$_line" == *"|"* ]] && { _saw_data=1; break; }
        fi
        _prev="$_line"
    done <<< "$text"

    if [[ $_hit_sep -eq 1 && $_saw_data -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

# Trim leading/trailing spaces from $1 -> _PSQL_TRIM
_psql_trim () {
    local v="$1"
    while [[ "$v" == " "* ]]; do v="${v# }"; done
    while [[ "$v" == *" " ]]; do v="${v% }"; done
    _PSQL_TRIM="$v"
}

# Split a "a | b | c" row on '|' into the global array _PSQL_CELLS (trimmed).
_psql_split () {
    local row="$1"
    _PSQL_CELLS=()
    local rest="$row" cell
    while [[ "$rest" == *"|"* ]]; do
        cell="${rest%%|*}"
        rest="${rest#*|}"
        _psql_trim "$cell"
        _PSQL_CELLS+=("$_PSQL_TRIM")
    done
    _psql_trim "$rest"
    _PSQL_CELLS+=("$_PSQL_TRIM")
}

strategy_extract () {
    local text="$1"
    local result="" entry=0

    # Locate the separator line and grab the header directly above it.
    local _prev="" _line header_line="" hit=0
    while IFS= read -r _line; do
        if _psql_is_separator "$_line" && [[ "$_prev" == *"|"* ]]; then
            header_line="$_prev"
            hit=1
            break
        fi
        _prev="$_line"
    done <<< "$text"
    [[ $hit -eq 1 ]] || return

    # Column names from the header row.
    _psql_split "$header_line"
    local col_names=() _c name
    for _c in "${_PSQL_CELLS[@]}"; do
        name="$_c"
        name="${name//./}"    # drop dots -- they break the tidy melt group key
        name="${name// /_}"   # spaces -> underscore
        col_names+=("$name")
    done
    local num_cols=${#col_names[@]}
    [[ $num_cols -lt 1 ]] && return

    # Data rows live after the separator. Skip until we pass the separator, then
    # consume rows containing '|'. Skip blanks, the "(N rows)" footer (no '|'),
    # and psql wrap/continuation lines (empty first cell).
    local past=0
    _prev=""
    while IFS= read -r _line; do
        if [[ $past -eq 0 ]]; then
            _psql_is_separator "$_line" && [[ "$_prev" == *"|"* ]] && past=1
            _prev="$_line"
            continue
        fi
        [[ "$_line" == *"|"* ]] || continue   # skips footer + blank lines

        _psql_split "$_line"
        # Continuation line for a wrapped cell: leading column is empty.
        [[ -z "${_PSQL_CELLS[0]}" ]] && continue

        entry=$((entry + 1))
        local i val
        for ((i=0; i<num_cols; i++)); do
            val="${_PSQL_CELLS[$i]}"
            _psql_trim "$val"; val="$_PSQL_TRIM"
            val="${val// /_}"
            [[ -z "$val" ]] && continue
            result+="entry${entry}.${col_names[$i]} ${val}"$'\n'
        done
    done <<< "$text"

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
