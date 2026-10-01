#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: box-table
## Description: Unicode box-drawing tables (│ cells, ─┼╭ borders) — mysql/psql unicode, rich, tabulate, duckdb, gum, pdm, glow, many modern CLIs
## Version: 2.0
## Priority: 34
## Sample: samples/box-table/basic.txt

# Modern Rust/Python CLIs render tables with Unicode box-drawing:
#
#   ╭──────────┬─────────╮   ┏━━━━┳━━━━━━━┓   ╔════╦═══════╗    id │ name    │ v
#   │ name     │ version │   ┃ id ┃ name  ┃   ║ id ║ name  ║   ────┼─────────┼───
#   ├──────────┼─────────┤   ┣━━━━╋━━━━━━━┫   ╠════╬═══════╣     1 │ django  │ 5
#   │ django   │ 5.0.6   │   ┃  1 ┃ django┃   ║  1 ║ django║     2 │ flask   │ 3
#   ╰──────────┴─────────╯   ┗━━━━┻━━━━━━━┛   ╚════╩═══════╝
#
# Same shape as psql-table's ASCII box, just different glyphs. The cell divider
# is one of the vertical box glyphs (│ ┃ ║ ┆ …); border/rule rows are runs of a
# horizontal glyph (─ ━ ═) with corner/joint glyphs, and some tools frame an
# ASCII `--- ` dash rule inside the box (csvlook). Rows may or may not carry an
# outer border (psql `linestyle unicode` has interior `│` only). We normalise the
# verticals to `|`, drop the rules, and emit one record per data row. Sources:
# mysql/psql unicode, duckdb, rich/textual, python `tabulate`
# (fancy_grid/rounded/double/presto), polars, csvlook, gum, glow, pdm. ASCII
# `+`/`-`/`|` tables stay with psql-table; this fires only when a box rule and a
# box-cell row coexist.

# Normalise every vertical cell divider (light/heavy/double/dotted) to ASCII '|'.
_box_norm () {
    local v="$1"
    v="${v//│/|}"; v="${v//┃/|}"; v="${v//║/|}"
    v="${v//┆/|}"; v="${v//┇/|}"; v="${v//┊/|}"; v="${v//┋/|}"; v="${v//╎/|}"; v="${v//╏/|}"
    _BOX_NORM="$v"
}

_box_trim () { local v="$1"; while [[ "$v" == " "* ]]; do v="${v# }"; done; while [[ "$v" == *" " ]]; do v="${v% }"; done; _BOX_TRIM="$v"; }

# Strip every box-drawing glyph (borders, corners, joints of all weights) plus
# spaces. A pure rule/border line reduces to empty.
_box_strip () {
    local s="$1"
    # verticals
    s="${s//│/}"; s="${s//┃/}"; s="${s//║/}"; s="${s//┆/}"; s="${s//┇/}"; s="${s//┊/}"; s="${s//┋/}"; s="${s//╎/}"; s="${s//╏/}"
    # horizontals
    s="${s//─/}"; s="${s//━/}"; s="${s//═/}"; s="${s//╌/}"; s="${s//╍/}"; s="${s//┄/}"; s="${s//┅/}"; s="${s//┈/}"; s="${s//┉/}"
    # light corners/joints
    s="${s//┌/}"; s="${s//┐/}"; s="${s//└/}"; s="${s//┘/}"; s="${s//├/}"; s="${s//┤/}"; s="${s//┬/}"; s="${s//┴/}"; s="${s//┼/}"
    # heavy corners/joints
    s="${s//┏/}"; s="${s//┓/}"; s="${s//┗/}"; s="${s//┛/}"; s="${s//┣/}"; s="${s//┫/}"; s="${s//┳/}"; s="${s//┻/}"; s="${s//╋/}"
    # double corners/joints
    s="${s//╔/}"; s="${s//╗/}"; s="${s//╚/}"; s="${s//╝/}"; s="${s//╠/}"; s="${s//╣/}"; s="${s//╦/}"; s="${s//╩/}"; s="${s//╬/}"
    # rounded + tabulate mixed joints
    s="${s//╭/}"; s="${s//╮/}"; s="${s//╰/}"; s="${s//╯/}"
    s="${s//╒/}"; s="${s//╕/}"; s="${s//╘/}"; s="${s//╛/}"; s="${s//╞/}"; s="${s//╡/}"; s="${s//╤/}"; s="${s//╧/}"; s="${s//╪/}"
    s="${s//╓/}"; s="${s//╖/}"; s="${s//╙/}"; s="${s//╜/}"; s="${s//╟/}"; s="${s//╢/}"; s="${s//╥/}"; s="${s//╨/}"; s="${s//╫/}"
    s="${s// /}"
    _BOX_STRIP="$s"
}

# Split a box row into _BOX_CELLS: normalise verticals to '|', drop any outer
# '|', split on the interior '|'s. Handles both bordered (│ a │ b │) and
# interior-only (a │ b │ c) rows.
_box_split () {
    _box_norm "$1"; _box_trim "$_BOX_NORM"
    local row="$_BOX_TRIM"
    # Strip the outer dividers only when the row is BRACKETED (a '|' at both
    # ends). An interior-only row with an empty leading/trailing cell (psql
    # `linestyle unicode`: "│ value …" where the first column is blank) keeps
    # its edge '|' so the empty cell is not silently dropped.
    [[ "$row" == "|"* && "$row" == *"|" ]] && { row="${row#|}"; row="${row%|}"; }
    _BOX_CELLS=()
    local rest="$row" cell
    while [[ "$rest" == *"|"* ]]; do
        cell="${rest%%|*}"; rest="${rest#*|}"
        _box_trim "$cell"; _BOX_CELLS+=("$_BOX_TRIM")
    done
    _box_trim "$rest"; _BOX_CELLS+=("$_BOX_TRIM")
}

# A rule/border line: a pure box rule (only box glyphs + spaces, carrying a
# horizontal run), OR a framed ASCII dash rule (`│ --- │ --- │`, csvlook).
_box_is_rule () {
    local l="$1"
    _box_strip "$l"
    if [[ -z "$_BOX_STRIP" ]]; then
        [[ "$l" == *─* || "$l" == *━* || "$l" == *═* || "$l" == *╌* || "$l" == *╍* \
           || "$l" == *┄* || "$l" == *┅* || "$l" == *┈* || "$l" == *┉* ]]
        return
    fi
    # framed dash rule: has a vertical divider and every split cell is dash-only.
    [[ "$l" == *│* || "$l" == *┃* || "$l" == *║* || "$l" == *┆* ]] || return 1
    [[ "$l" == *-* ]] || return 1
    _box_split "$l"
    [[ ${#_BOX_CELLS[@]} -ge 1 ]] || return 1
    local _c
    for _c in "${_BOX_CELLS[@]}"; do
        [[ "$_c" == *-* ]] || return 1
        local s="${_c//-/}"; s="${s//:/}"; s="${s// /}"
        [[ -z "$s" ]] || return 1
    done
    return 0
}

# A data/header row: carries a vertical box divider and is not a pure rule.
_box_is_row () {
    local l="$1"
    [[ "$l" == *│* || "$l" == *┃* || "$l" == *║* || "$l" == *┆* || "$l" == *┇* \
       || "$l" == *┊* || "$l" == *┋* || "$l" == *╎* || "$l" == *╏* ]] || return 1
    _box_is_rule "$l" && return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="unicode box-drawing table (│/┃/║ cells + ─/━/═ borders)"
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # PREFILTER (exact): acceptance needs a cell row, and _box_is_row demands
    # one of these vertical dividers on the line — no divider anywhere in the
    # text means no cell row, so decline without the per-line walk.
    case "$text" in
        *│*|*┃*|*║*|*┆*|*┇*|*┊*|*┋*|*╎*|*╏*) ;;
        *) return 1 ;;
    esac
    local _line _saw_rule=0 _saw_cell=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ "${_line}" != *[![:space:]]* ]] && continue
        if _box_is_rule "$_line"; then _saw_rule=1
        elif _box_is_row "$_line"; then _saw_cell=1; fi
    done
    if [[ $_saw_rule -eq 1 && $_saw_cell -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1" result="" entry=0 _line
    # modal cell count across box rows (rules excluded)
    local counts=()
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        _box_is_row "$_line" || continue
        _box_split "$_line"; counts+=("${#_BOX_CELLS[@]}")
    done
    _line=""
    [[ ${#counts[@]} -lt 2 ]] && return
    local modal=0 best=0
    _fr_modal "${counts[@]}"; modal=$_FR_MODE; best=$_FR_MODE_N
    [[ $modal -lt 1 ]] && return

    local col_names=() num_cols=0 have_header=0 _c name i val
    while IFS= read -r _line; do
        _box_is_row "$_line" || continue
        _box_split "$_line"
        [[ ${#_BOX_CELLS[@]} -ne $modal ]] && continue
        if [[ $have_header -eq 0 ]]; then
            for _c in "${_BOX_CELLS[@]}"; do
                name="$_c"; name="${name//./}"; name="${name// /_}"
                while [[ "$name" == *__* ]]; do name="${name//__/_}"; done
                name="${name#_}"; name="${name%_}"
                [[ -z "$name" ]] && name="$(_col_letter $((${#col_names[@]} + 1)))"
                col_names+=("$name")
            done
            num_cols=${#col_names[@]}; have_header=1; continue
        fi
        # Skip a duckdb/clickhouse "type row" — the line of column types printed
        # under the names, before the header/data separator rule (every cell is a
        # bare SQL type keyword). Only the row immediately after the header.
        if [[ $entry -eq 0 ]]; then
            local _allty=1 _tc
            for _tc in "${_BOX_CELLS[@]}"; do
                case "${_tc%%(*}" in
                    varchar|char|text|string|blob|bytea|uuid|json|jsonb|xml|bool|boolean|bit \
                    |int|integer|tinyint|smallint|bigint|hugeint|int2|int4|int8|serial \
                    |float|float4|float8|double|real|decimal|numeric|number \
                    |date|time|timestamp|timestamptz|datetime|interval|enum|array|map|struct) : ;;
                    *) _allty=0; break ;;
                esac
            done
            [[ $_allty -eq 1 ]] && continue
        fi
        entry=$((entry + 1))
        for ((i = 0; i < num_cols; i++)); do
            val="${_BOX_CELLS[$i]}"; _box_trim "$val"; val="$_BOX_TRIM"
            [[ -z "$val" ]] && continue
            result+="entry${entry}.${col_names[$i]} ${val}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
