#!/bin/bash
## Name: box-table
## Description: Unicode box-drawing tables (│ cells, ─┼╭ borders) — pdm, gum, glow, many modern CLIs
## Version: 1.0
## Priority: 34
## Sample: samples/box-table/basic.txt

# Modern Rust/Python CLIs render tables with Unicode box-drawing:
#
#   ╭──────────┬─────────╮
#   │ name     │ version │
#   ├──────────┼─────────┤
#   │ django   │ 5.0.6   │
#   ╰──────────┴─────────╯
#
# Same shape as psql-table's ASCII box, just different glyphs: `│` is the cell
# delimiter and the border/rule rows are made of ─ plus corner/joint glyphs
# (┌┐└┘├┤┬┴┼╭╮╰╯ and the heavy/double variants). We recognize those, drop the
# rules, and emit one record per data row. ASCII `+`/`-`/`|` tables stay with
# psql-table; this only fires when a genuine `─`-run rule and a `│` row exist.

# A rule row is only box-drawing glyphs + spaces, containing a run of ─.
_box_is_rule () {
    local l="$1"
    [[ "$l" == *"─"* ]] || return 1
    # after removing every box glyph and space, nothing should remain
    local s="$l"
    s="${s//─/}"; s="${s//│/}"; s="${s//┼/}"; s="${s//┬/}"; s="${s//┴/}"
    s="${s//├/}"; s="${s//┤/}"; s="${s//┌/}"; s="${s//┐/}"; s="${s//└/}"; s="${s//┘/}"
    s="${s//╭/}"; s="${s//╮/}"; s="${s//╰/}"; s="${s//╯/}"
    s="${s//═/}"; s="${s//╬/}"; s="${s//╞/}"; s="${s//╡/}"; s="${s// /}"
    [[ -z "$s" ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local _line _saw_rule=0 _saw_cell=0
    while IFS= read -r _line; do
        if _box_is_rule "$_line"; then _saw_rule=1
        elif [[ "$_line" == *"│"* ]]; then _saw_cell=1; fi
    done <<< "$text"
    if [[ $_saw_rule -eq 1 && $_saw_cell -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

_box_trim () { local v="$1"; while [[ "$v" == " "* ]]; do v="${v# }"; done; while [[ "$v" == *" " ]]; do v="${v% }"; done; _BOX_TRIM="$v"; }

# Split a `│ a │ b │` row into _BOX_CELLS (inner cells, trimmed).
_box_split () {
    local row="$1"
    _box_trim "$row"; row="$_BOX_TRIM"
    [[ "$row" == "│"* ]] && row="${row#│}"
    [[ "$row" == *"│" ]] && row="${row%│}"
    _BOX_CELLS=()
    local rest="$row" cell
    while [[ "$rest" == *"│"* ]]; do
        cell="${rest%%│*}"; rest="${rest#*│}"
        _box_trim "$cell"; _BOX_CELLS+=("$_BOX_TRIM")
    done
    _box_trim "$rest"; _BOX_CELLS+=("$_BOX_TRIM")
}

strategy_extract () {
    local text="$1" result="" entry=0 _line
    # modal cell count across non-rule │-rows
    local counts=()
    while IFS= read -r _line; do
        [[ "$_line" == *"│"* ]] || continue
        _box_is_rule "$_line" && continue
        _box_split "$_line"; counts+=("${#_BOX_CELLS[@]}")
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
        [[ "$_line" == *"│"* ]] || continue
        _box_is_rule "$_line" && continue
        _box_split "$_line"
        [[ ${#_BOX_CELLS[@]} -ne $modal ]] && continue
        if [[ $have_header -eq 0 ]]; then
            for _c in "${_BOX_CELLS[@]}"; do
                name="$_c"; name="${name//./}"; name="${name// /_}"
                [[ -z "$name" ]] && name="$(_col_letter $((${#col_names[@]} + 1)))"
                col_names+=("$name")
            done
            num_cols=${#col_names[@]}; have_header=1; continue
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
