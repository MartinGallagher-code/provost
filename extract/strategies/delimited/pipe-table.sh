#!/bin/bash
## Name: pipe-table
## Description: GitHub-flavored markdown tables (| a | b | with a |---|---| rule) — BenchmarkDotNet, doc-gen CLIs
## Version: 1.0
## Priority: 33
## Sample: samples/pipe-table/basic.txt

# Markdown pipe tables — the format many tools print (BenchmarkDotNet, glow,
# `column`-style doc generators, GitHub rendering):
#
#   | Method     | Mean      | Allocated |
#   |----------- |----------:|----------:|
#   | ParseSmall |  14.42 us |     512 B |
#   | ParseLarge | 448.21 us |   10248 B |
#
# Rows are wrapped in leading/trailing `│`... no — leading/trailing `|`, with a
# separator rule of `-`/`:`/`|`/space only. This is a distinct dialect from
# psql-table (`a | b` with a `---+---` rule and NO outer pipes): a pipe-table
# row is bracketed by `|` and its rule carries no `+` joints. We drop the rule,
# take the first row as the header, and emit one record per data row.

# A rule row: trimmed, made only of |, -, :, and spaces, and contains a '-'.
_pt_is_rule () {
    local l="$1"
    l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
    [[ "$l" == *-* ]] || return 1
    local s="$l"; s="${s//|/}"; s="${s//-/}"; s="${s//:/}"; s="${s// /}"
    [[ -z "$s" ]]
}

# A table row: trimmed, starts and ends with '|', and has >=2 pipes (>=1 cell).
_pt_is_row () {
    local l="$1"
    l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
    [[ "$l" == "|"*"|" ]] || return 1
    local rest="${l#|}"; [[ "$rest" == *"|"* ]]
}

_pt_trim () { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; _PT_TRIM="$v"; }

# Split a `| a | b |` row into _PT_CELLS (inner cells, trimmed).
_pt_split () {
    local row="$1"
    _pt_trim "$row"; row="$_PT_TRIM"
    row="${row#|}"; row="${row%|}"
    _PT_CELLS=()
    local rest="$row" cell
    while [[ "$rest" == *"|"* ]]; do
        cell="${rest%%|*}"; rest="${rest#*|}"
        _pt_trim "$cell"; _PT_CELLS+=("$_PT_TRIM")
    done
    _pt_trim "$rest"; _PT_CELLS+=("$_PT_TRIM")
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="markdown pipe table (| a | b | rows + |---| rule)"
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local _line _saw_rule=0 _saw_row=0
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        if _pt_is_rule "$_line" && [[ "$_line" == *"|"* ]]; then _saw_rule=1
        elif _pt_is_row "$_line"; then _saw_row=1; fi
    done <<< "$text"
    if [[ $_saw_rule -eq 1 && $_saw_row -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1" result="" entry=0 _line
    # modal cell count across non-rule pipe rows
    local counts=()
    while IFS= read -r _line; do
        _pt_is_row "$_line" || continue
        _pt_is_rule "$_line" && continue
        _pt_split "$_line"; counts+=("${#_PT_CELLS[@]}")
    done <<< "$text"
    [[ ${#counts[@]} -lt 2 ]] && return
    local modal=0 best=0 a b k
    for a in "${counts[@]}"; do
        k=0; for b in "${counts[@]}"; do [[ "$b" -eq "$a" ]] && k=$((k + 1)); done
        [[ $k -gt $best ]] && { best=$k; modal=$a; }
    done
    [[ $modal -lt 1 ]] && return

    local col_names=() num_cols=0 have_header=0 _c name i val
    while IFS= read -r _line; do
        _pt_is_row "$_line" || continue
        _pt_is_rule "$_line" && continue
        _pt_split "$_line"
        [[ ${#_PT_CELLS[@]} -ne $modal ]] && continue
        if [[ $have_header -eq 0 ]]; then
            for _c in "${_PT_CELLS[@]}"; do
                name="$_c"; name="${name//./}"; name="${name// /_}"
                while [[ "$name" == *__* ]]; do name="${name//__/_}"; done
                name="${name#_}"; name="${name%_}"
                [[ -z "$name" ]] && name="$(_col_letter $((${#col_names[@]} + 1)))"
                col_names+=("$name")
            done
            num_cols=${#col_names[@]}; have_header=1; continue
        fi
        entry=$((entry + 1))
        for ((i = 0; i < num_cols; i++)); do
            val="${_PT_CELLS[$i]}"; _pt_trim "$val"; val="$_PT_TRIM"
            [[ -z "$val" ]] && continue
            result+="entry${entry}.${col_names[$i]} ${val}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
