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

# A TOP border that carries the column names (clickhouse PrettyCompact):
#   ┌─name───────┬─type────┬─────rows─┐
# No vertical cell divider, opens with a top-left corner, has a horizontal run,
# and strips to text. The names are the segments between the top joints; they
# fill _BOX_BNAMES (trimmed, in order). Returns 1 for anything else — a plain
# border, a rich panel title (`╭── Title ──╮`: one segment) is left as is.
_box_border_names () {
    local l="$1"
    _BOX_BNAMES=()
    _box_trim "$l"; l="$_BOX_TRIM"
    case "$l" in ┌*|┏*|╔*|╭*|╒*|╓*) ;; *) return 1 ;; esac
    case "$l" in *│*|*┃*|*║*|*┆*|*┇*|*┊*|*┋*|*╎*|*╏*) return 1 ;; esac
    case "$l" in *─*|*━*|*═*) ;; *) return 1 ;; esac
    _box_strip "$l"; [[ -n "$_BOX_STRIP" ]] || return 1
    local v="$l"
    v="${v//┬/|}"; v="${v//┳/|}"; v="${v//╦/|}"; v="${v//╤/|}"; v="${v//╥/|}"
    [[ "$v" == *"|"* ]] || return 1
    v="${v//─/ }"; v="${v//━/ }"; v="${v//═/ }"
    v="${v//┌/}"; v="${v//┐/}"; v="${v//┏/}"; v="${v//┓/}"; v="${v//╔/}"; v="${v//╗/}"
    v="${v//╭/}"; v="${v//╮/}"; v="${v//╒/}"; v="${v//╕/}"; v="${v//╓/}"; v="${v//╖/}"
    local rest="$v" cell
    while [[ "$rest" == *"|"* ]]; do
        cell="${rest%%|*}"; rest="${rest#*|}"
        _box_trim "$cell"; _BOX_BNAMES+=("$_BOX_TRIM")
    done
    _box_trim "$rest"; _BOX_BNAMES+=("$_BOX_TRIM")
    return 0
}

# _box_gap_split CELL — split a cell on runs of 2+ spaces into _BOX_PARTS
# (a box cell that itself holds aligned sub-columns: `cpu%   mem%`).
_box_gap_split () {
    local v="$1"
    v="${v//  /$'\t'}"
    while [[ "$v" == *$'\t '* ]]; do v="${v//$'\t '/$'\t'}"; done
    while [[ "$v" == *$'\t\t'* ]]; do v="${v//$'\t\t'/$'\t'}"; done
    _BOX_PARTS=()
    local IFS=$'\t'
    read -r -a _BOX_PARTS <<< "$v"
}

# _box_cell_starts ROW — byte offsets of each cell's left divider in the
# normalised row (every box vertical is one 3-byte glyph, so two rows of
# ASCII text keep comparable offsets after _box_norm). Fills _BOX_STARTS.
_box_cell_starts () {
    _box_norm "$1"
    local v="$_BOX_NORM" i
    _BOX_STARTS=()
    for ((i = 0; i < ${#v}; i++)); do
        [[ "${v:i:1}" == "|" ]] && _BOX_STARTS+=("$i")
    done
}

# A label cell of a key/value box: a capitalised word or short phrase
# ("Package", "Vulnerable versions", "More info", "CVE-ID").
_box_is_label () {
    local c="$1"
    [[ "$c" =~ ^[A-Z][A-Za-z0-9_-]*([ ][A-Za-z0-9_-]+){0,3}$ ]]
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

    # KEY/VALUE BOX with a TITLE row (pnpm/npm audit): a two-column box whose
    # first row is set off by a rule and is a title, not column names, and
    # whose other rows are label/value pairs:
    #   │ high                │ Prototype Pollution │   <- title (severity, title)
    #   ├─────────────────────┼─────────────────────┤
    #   │ Package             │ lodash              │   <- label / value
    #   │ Vulnerable versions │ <4.17.21            │
    # It is a column-name row only when it reads like one (every cell one
    # word); here a cell is a phrase. Every row then is a (key, value) record,
    # the title row included, with a `box` index when several boxes repeat.
    local kvbox=0 nbox=0
    if [[ $modal -eq 2 ]]; then
        local _st=0 _hdr_phrase=0 _nlab=0 _labs="|" _okkv=1
        for _line in "${_FR_LINES[@]}"; do
            [[ "$_line" != *[![:space:]]* ]] && continue
            _box_trim "$_line"
            case "$_BOX_TRIM" in ┌*|┏*|╔*|╭*|╒*|╓*) nbox=$((nbox + 1)); _st=0; continue ;; esac
            if _box_is_rule "$_line"; then
                [[ $_st -eq 1 ]] && _st=2
                continue
            fi
            _box_is_row "$_line" || { _okkv=0; break; }
            _box_split "$_line"
            [[ ${#_BOX_CELLS[@]} -eq 2 ]] || { _okkv=0; break; }
            if [[ $_st -eq 0 ]]; then
                [[ "${_BOX_CELLS[0]}" == *" "* || "${_BOX_CELLS[1]}" == *" "* ]] && _hdr_phrase=1
                _st=1; continue
            fi
            [[ $_st -eq 2 ]] || { _okkv=0; break; }
            _box_is_label "${_BOX_CELLS[0]}" || { _okkv=0; break; }
            [[ "$_labs" == *"|${_BOX_CELLS[0]}|"* && $nbox -le 1 ]] && { _okkv=0; break; }
            _labs+="${_BOX_CELLS[0]}|"; _nlab=$((_nlab + 1))
        done
        [[ $_okkv -eq 1 && $_hdr_phrase -eq 1 && $_nlab -ge 2 && $nbox -ge 1 ]] && kvbox=1
    fi
    if [[ $kvbox -eq 1 ]]; then
        local _bi=0
        for _line in "${_FR_LINES[@]}"; do
            [[ "$_line" != *[![:space:]]* ]] && continue
            _box_trim "$_line"
            case "$_BOX_TRIM" in ┌*|┏*|╔*|╭*|╒*|╓*) _bi=$((_bi + 1)); continue ;; esac
            _box_is_row "$_line" || continue
            _box_split "$_line"
            entry=$((entry + 1))
            [[ $nbox -gt 1 ]] && result+="entry${entry}.box ${_bi}"$'\n'
            [[ -n "${_BOX_CELLS[0]}" ]] && result+="entry${entry}.key ${_BOX_CELLS[0]}"$'\n'
            [[ -n "${_BOX_CELLS[1]}" ]] && result+="entry${entry}.value ${_BOX_CELLS[1]}"$'\n'
        done
        result+="total_entries ${entry}"$'\n'
        echo "$result"
        return
    fi

    # TWO-ROW GROUPED HEADER: the rows between the top border and the first
    # rule are a GROUP row over a FIELD row —
    #   ║            ║    CURRENT     ║     PEAK       ║   (group; spans or blanks)
    #   ║ PROC       ║  cpu%   mem%   ║  cpu%   mem%   ║   (field)
    #   ╠════════════╬════════════════╬════════════════╣
    # Each column is named group_field. A group cell spanning several field
    # cells (fewer group cells than fields) is mapped by divider offset. When
    # a field cell holds 2+-space-separated sub-labels and every data cell
    # below splits the same way, the column is split into those sub-columns.
    local _grp=0 _g1="" _g2="" _gl1=-1 _gl2=-1
    local _gk=0 _gn=0 _gr=0 _gsaw_rule=0
    for _line in "${_FR_LINES[@]}"; do
        _gk=$((_gk + 1))
        [[ "$_line" != *[![:space:]]* ]] && continue
        _box_border_names "$_line" && { _gn=0; break; }
        if _box_is_rule "$_line"; then
            [[ $_gn -ge 1 ]] && { _gsaw_rule=1; break; }
            continue
        fi
        _box_is_row "$_line" || { _gn=0; break; }
        _gn=$((_gn + 1))
        [[ $_gn -eq 1 ]] && { _g1="$_line"; _gl1=$_gk; }
        [[ $_gn -eq 2 ]] && { _g2="$_line"; _gl2=$_gk; }
        [[ $_gn -gt 2 ]] && break
    done
    local _gnames=() _gsub=()
    if [[ $_gn -eq 2 && $_gsaw_rule -eq 1 && $modal -ge 2 ]]; then
        local _c1=() _c2=() _gok=1 _gempty=0 _gfull=0
        _box_split "$_g1"; _c1=("${_BOX_CELLS[@]}")
        _box_split "$_g2"; _c2=("${_BOX_CELLS[@]}")
        [[ ${#_c2[@]} -eq $modal && ${#_c1[@]} -ge 2 && ${#_c1[@]} -le $modal ]] || _gok=0
        for _c in "${_c1[@]}"; do [[ -z "$_c" ]] && _gempty=1 || _gfull=1; done
        for _c in "${_c2[@]}"; do
            [[ -z "$_c" || "$_c" =~ ^[0-9.,%+-]+$ ]] && { _gok=0; break; }
        done
        [[ $_gfull -eq 1 ]] || _gok=0
        [[ $_gempty -eq 1 || ${#_c1[@]} -lt $modal ]] || _gok=0
        if [[ $_gok -eq 1 ]]; then
            local _gs1=() _gs2=() _j _k _grpname
            if [[ ${#_c1[@]} -lt $modal ]]; then
                _box_cell_starts "$_g1"; _gs1=("${_BOX_STARTS[@]}")
                _box_cell_starts "$_g2"; _gs2=("${_BOX_STARTS[@]}")
                # an interior-only row has no outer divider: offsets are
                # unusable — leave the table to the plain path
                [[ ${#_gs1[@]} -eq $(( ${#_c1[@]} + 1 )) && ${#_gs2[@]} -eq $(( modal + 1 )) ]] || _gok=0
            fi
        fi
        if [[ $_gok -eq 1 ]]; then
            for ((_j = 0; _j < modal; _j++)); do
                _grpname=""
                if [[ ${#_c1[@]} -eq $modal ]]; then
                    _grpname="${_c1[$_j]}"
                else
                    for ((_k = 0; _k < ${#_c1[@]}; _k++)); do
                        if [[ ${_gs2[$_j]} -ge ${_gs1[$_k]} && ${_gs2[$_j]} -lt ${_gs1[$((_k + 1))]} ]]; then
                            _grpname="${_c1[$_k]}"; break
                        fi
                    done
                fi
                _gnames+=("${_grpname:+${_grpname}_}${_c2[$_j]}")
                _gsub+=(0)
            done
            # sub-columns: only for the same-count layout (one group per cell)
            if [[ ${#_c1[@]} -eq $modal ]]; then
                local _drows=() _dk=0 _dl
                for _dl in "${_FR_LINES[@]}"; do
                    _dk=$((_dk + 1))
                    [[ $_dk -le $_gl2 ]] && continue
                    _box_is_row "$_dl" || continue
                    _box_split "$_dl"; [[ ${#_BOX_CELLS[@]} -eq $modal ]] || continue
                    _drows+=("$_dl")
                done
                for ((_j = 0; _j < modal; _j++)); do
                    _box_gap_split "${_c2[$_j]}"; local _np=${#_BOX_PARTS[@]}
                    [[ $_np -ge 2 && ${#_drows[@]} -ge 1 ]] || continue
                    local _sok=1
                    for _dl in "${_drows[@]}"; do
                        _box_split "$_dl"; _box_gap_split "${_BOX_CELLS[$_j]}"
                        [[ ${#_BOX_PARTS[@]} -eq $_np ]] || { _sok=0; break; }
                    done
                    [[ $_sok -eq 1 ]] && _gsub[$_j]=$_np
                done
            fi
            _grp=1
        fi
    fi

    local col_names=() num_cols=0 have_header=0 _c name i val _bnames=() _ln=0 _colmap=() _subidx=()
    if [[ $_grp -eq 1 ]]; then
        local _gj _gp _gpre
        _box_split "$_g2"; local _f2=("${_BOX_CELLS[@]}")
        for ((_gj = 0; _gj < modal; _gj++)); do
            if [[ ${_gsub[$_gj]} -ge 2 ]]; then
                _gpre="${_gnames[$_gj]%"${_f2[$_gj]}"}"
                _box_gap_split "${_f2[$_gj]}"; local _parts=("${_BOX_PARTS[@]}")
                for ((_gp = 0; _gp < ${#_parts[@]}; _gp++)); do
                    name="${_parts[$_gp]}"
                    [[ "$name" == *[A-Za-z0-9]* ]] || name="$(_col_letter $((_gp + 1)))"
                    col_names+=("${_gpre}${name}"); _colmap+=("$_gj"); _subidx+=("$_gp")
                done
            else
                col_names+=("${_gnames[$_gj]}"); _colmap+=("$_gj"); _subidx+=(-1)
            fi
        done
        for ((_gj = 0; _gj < ${#col_names[@]}; _gj++)); do
            name="${col_names[$_gj]}"; name="${name//./}"; name="${name// /_}"
            while [[ "$name" == *__* ]]; do name="${name//__/_}"; done
            name="${name#_}"; name="${name%_}"
            [[ -z "$name" ]] && name="$(_col_letter $((_gj + 1)))"
            col_names[$_gj]="$name"
        done
        num_cols=${#col_names[@]}; have_header=1
    fi
    while IFS= read -r _line; do
        _ln=$((_ln + 1))
        if [[ $_grp -eq 1 ]]; then
            [[ $_ln -le $_gl2 ]] && continue
            _box_is_row "$_line" || continue
            _box_split "$_line"
            [[ ${#_BOX_CELLS[@]} -ne $modal ]] && continue
            local _rc=("${_BOX_CELLS[@]}") _sj
            entry=$((entry + 1))
            for ((i = 0; i < num_cols; i++)); do
                _sj=${_colmap[$i]}
                if [[ ${_subidx[$i]} -ge 0 ]]; then
                    _box_gap_split "${_rc[$_sj]}"; val="${_BOX_PARTS[${_subidx[$i]}]:-}"
                else
                    val="${_rc[$_sj]}"
                fi
                _box_trim "$val"; val="$_BOX_TRIM"
                [[ -z "$val" ]] && continue
                result+="entry${entry}.${col_names[$i]} ${val}"$'\n'
            done
            continue
        fi
        # A top border that carries the column names (clickhouse): it IS the
        # header, so the first cell row is data. A later block's border
        # repeating the names is skipped like any border.
        if [[ $have_header -eq 0 ]] && _box_border_names "$_line"; then
            _bnames=("${_BOX_BNAMES[@]}"); continue
        fi
        _box_is_row "$_line" || continue
        _box_split "$_line"
        [[ ${#_BOX_CELLS[@]} -ne $modal ]] && continue
        if [[ $have_header -eq 0 && ${#_bnames[@]} -eq $modal && $modal -ge 2 ]]; then
            for _c in "${_bnames[@]}"; do
                name="$_c"; name="${name//./}"; name="${name// /_}"
                while [[ "$name" == *__* ]]; do name="${name//__/_}"; done
                name="${name#_}"; name="${name%_}"
                [[ -z "$name" ]] && name="$(_col_letter $((${#col_names[@]} + 1)))"
                col_names+=("$name")
            done
            num_cols=${#col_names[@]}; have_header=1
        fi
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
                    |int16|int32|int64|int128|uint8|uint16|uint32|uint64|utinyint|usmallint|uinteger|ubigint \
                    |float32|float64 \
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
