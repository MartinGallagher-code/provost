#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: psql-table
## Description: Pipe-delimited box tables with a ---+--- separator (psql, mysql \G-less output)
## Version: 1.0
## Priority: 35
## Sample: samples/psql-table/basic.txt

# Is a line a box-table separator? Only '-'/'=', '+', and spaces, with at least
# one '+' joint and a run of the rule char -- e.g. "----+----+----",
# "+----+----+", or airflow's equals rule "====+====+====".
_psql_is_separator () {
    local l="$1"
    [[ "$l" == *"+"* ]] || return 1
    [[ "$l" =~ ^[-=+\ ]+$ ]] || return 1
    [[ "$l" == *"---"* || "$l" == *"==="* ]] || return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Walk lines keeping the previous line so we can confirm the row above the
    # separator carries a '|' column delimiter, and that at least one row below
    # does too. Only then is this a genuine pipe box table.
    local _prev="" _line _sep_hdr="" _saw_data=0 _hit_sep=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        if [[ $_hit_sep -eq 0 ]]; then
            if _psql_is_separator "$_line"; then
                [[ "$_prev" == *"|"* ]] || { _prev="$_line"; continue; }
                _hit_sep=1
            fi
        else
            [[ "$_line" == *"|"* ]] && { _saw_data=1; break; }
        fi
        _prev="$_line"
    done

    if [[ $_hit_sep -eq 1 && $_saw_data -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=80
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

# Split a box-table row into the global array _PSQL_CELLS (trimmed). Strips one
# outer '|' border on each side first, so `| a | b |` (mysql / aws --output table)
# and `a | b` (psql) both yield the same inner cells.
_psql_split () {
    local row="$1"
    _psql_trim "$row"; row="$_PSQL_TRIM"
    # Strip outer '|' borders only for a FULL box row (both ends piped, e.g.
    # `| a | b |` from mysql / aws --output table). A psql row has no leading '|',
    # so its trailing '|' denotes a genuine empty last column and must be kept.
    local _lead=0
    [[ "$row" == "|"* ]] && { row="${row#|}"; _lead=1; }
    [[ $_lead -eq 1 && "$row" == *"|" ]] && row="${row%|}"
    # Split on '|' EXCEPT a backslash-escaped '\|' — SQL result cells legitimately
    # contain literal bars (regex alternations, `s1 || s2` concat expressions) and
    # psql-style renderers escape them as '\|'. A naive split shreds such a row
    # into extra cells, pushing it off the modal width so it's silently DROPPED.
    # The escape is table-encoding, so the emitted cell carries the bare '|'.
    _PSQL_CELLS=()
    local cell="" i c n=${#row}
    for ((i = 0; i < n; i++)); do
        c="${row:$i:1}"
        if [[ "$c" == '\' && "${row:$((i + 1)):1}" == '|' ]]; then
            cell+='|'; i=$((i + 1))
        elif [[ "$c" == '|' ]]; then
            _psql_trim "$cell"; _PSQL_CELLS+=("$_PSQL_TRIM"); cell=""
        else
            cell+="$c"
        fi
    done
    _psql_trim "$cell"
    _PSQL_CELLS+=("$_PSQL_TRIM")
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _line

    # Collect every '|'-bearing, non-separator row's cell count. A box table's
    # data/header rows share a modal cell count; a single-cell title banner
    # (`aws --output table`'s "DescribeInstances") and the `(N rows)` footer /
    # blanks / rules fall outside it and are dropped.
    local counts=() _n
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ "$_line" == *"|"* ]] || continue
        _psql_is_separator "$_line" && continue
        _psql_split "$_line"
        counts+=("${#_PSQL_CELLS[@]}")
    done
    _line=""
    [[ ${#counts[@]} -lt 2 ]] && return

    local modal=0 best=0
    _fr_modal "${counts[@]}"; modal=$_FR_MODE; best=$_FR_MODE_N
    [[ $modal -lt 1 ]] && return

    # First modal-width row is the header; the rest (modal width, non-continuation)
    # are data. A psql wrapped-cell continuation line has an empty first cell.
    local col_names=() num_cols=0 have_header=0 _c name i val
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ "$_line" == *"|"* ]] || continue
        _psql_is_separator "$_line" && continue
        _psql_split "$_line"
        [[ ${#_PSQL_CELLS[@]} -ne $modal ]] && continue    # skip title/odd rows

        if [[ $have_header -eq 0 ]]; then
            for _c in "${_PSQL_CELLS[@]}"; do
                name="$_c"; name="${name//./}"; name="${name// /_}"
                [[ -z "$name" ]] && name="$(_col_letter $((${#col_names[@]} + 1)))"
                col_names+=("$name")
            done
            num_cols=${#col_names[@]}
            have_header=1
            continue
        fi

        [[ -z "${_PSQL_CELLS[0]}" ]] && continue           # psql continuation row
        entry=$((entry + 1))
        for ((i = 0; i < num_cols; i++)); do
            val="${_PSQL_CELLS[$i]}"
            _psql_trim "$val"; val="$_PSQL_TRIM"
            [[ -z "$val" ]] && continue
            result+="entry${entry}.${col_names[$i]} ${val}"$'\n'
        done
    done
    _line=""

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
