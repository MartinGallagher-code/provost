#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

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

# --- bare dialect: `a | b | c` rows with NO outer pipes and NO rule row ------
#
#   name | pattern | action
#   http | ^GET\|POST$ | allow
#
# A second pipe dialect many CLIs print: cells joined by ' | ' with no border
# pipes and no separator rule, where in-cell bars are protected by a backslash
# (`\|`) or double quotes (`"a|b"`). Detection is deliberately strict — this
# shape is one stray '|' away from prose — see _pt_bare_shape.

# Split a bare row into _PT_CELLS: '|' separates at top level; '\|' is a literal
# bar (escape dropped); a double-quoted span protects everything inside it
# (quotes kept — they are cell content, stripping is the melt's call).
_pt_split_bare () {
    local row="$1"
    local cell="" i c inq=0 n=${#row}
    _PT_CELLS=()
    for ((i = 0; i < n; i++)); do
        c="${row:$i:1}"
        if [[ "$c" == '\' && "${row:$((i + 1)):1}" == '|' ]]; then
            cell+='|'; i=$((i + 1))
        elif [[ "$c" == '"' ]]; then
            inq=$((1 - inq)); cell+='"'
        elif [[ "$c" == '|' && $inq -eq 0 ]]; then
            _pt_trim "$cell"; _PT_CELLS+=("$_PT_TRIM"); cell=""
        else
            cell+="$c"
        fi
    done
    _pt_trim "$cell"; _PT_CELLS+=("$_PT_TRIM")
}

# Slurm's --parsable dialect (`sacct -p`, `sacctmgr -p`, `sreport -p`, `sshare
# -p`) ends EVERY line with the delimiter, the header included:
#
#   JobID|JobName|State|ExitCode|
#   1|osu_bw|COMPLETED|0:0|
#
# That terminating bar is not a cell. Set _PT_TERM=1 when every non-blank,
# non-rule line ends in `|` and none starts with one (a leading bar is the
# markdown/box dialects'); the bare paths then drop one trailing bar per line.
# A header ending in `|` is the signal: in `-P` output (no terminator) only a
# data row with an empty last cell ends in a bar, never the header.
_pt_term_shape () {
    local text="$1" _line _n=0
    _PT_TERM=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ "${_line}" != *[![:space:]]* ]] && continue
        _pt_is_rule "$_line" && continue
        _pt_trim "$_line"; _line="$_PT_TRIM"
        [[ "$_line" == "|"* || "$_line" != *"|" ]] && return 0
        _n=$((_n + 1))
    done
    [[ $_n -ge 2 ]] && _PT_TERM=1
    return 0
}

# Is this text a bare pipe table? Yes only when EVERY non-blank line: does not
# start or end with '|' (that's the markdown/box dialects' territory), contains
# no `---+---` rule (psql-table's anchor), and splits (escape/quote-aware) into
# the SAME >=2 top-level cell count — across >=3 lines. Sets _PT_BARE_COLS.
_pt_bare_shape () {
    local text="$1" _line lines=0 want=-1 _c
    _PT_BARE_COLS=0
    _pt_term_shape "$text"
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ "${_line}" != *[![:space:]]* ]] && continue
        # (a `-----|-----` rule — istanbul/nyc/c8 text reports draw one above
        # and below the header and under the last row — is chrome, not a row)
        _pt_is_rule "$_line" && continue
        # (a result-set footer under the rows — `(3 rows)` — is no row)
        [[ $lines -ge 2 && "$_line" != *"|"* ]] && _fr_is_footer "$_line" && continue
        _pt_trim "$_line"; _line="$_PT_TRIM"
        # (Slurm --parsable: every line's terminating bar is no cell)
        [[ $_PT_TERM -eq 1 ]] && _line="${_line%|}"
        [[ "$_line" == "|"* ]] && return 1
        # A trailing `|` on a DATA row is an empty last cell (`sacct -P`'s
        # `…|02:14:33|` with no MaxRSS) — still the header's cell count, so
        # the count check below decides. Only the header may not end in one
        # (with no leading bar, a bar-terminated header is no table shape) —
        # unless EVERY line does, which is `sacct -p` (see _pt_term_shape).
        [[ $want -lt 0 && "$_line" == *"|" ]] && return 1
        [[ "$_line" == *"---+---"* ]] && return 1
        _pt_split_bare "$_line"
        [[ ${#_PT_CELLS[@]} -lt 2 ]] && return 1
        # A trimmed cell with an INTERNAL run of 2+ spaces isn't a table cell —
        # it's a TUI gauge line (`CPU     45.2%  |####...|  user: …`) whose bars
        # merely look like pipes. Real bare-table cells are compact.
        for _c in "${_PT_CELLS[@]}"; do [[ "$_c" =~ [\ ]{2,} ]] && return 1; done
        if [[ $want -lt 0 ]]; then want=${#_PT_CELLS[@]}
        elif [[ ${#_PT_CELLS[@]} -ne $want ]]; then return 1; fi
        lines=$((lines + 1))
    done
    [[ $lines -ge 3 ]] || return 1
    _PT_BARE_COLS=$want
    return 0
}

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
    # PREFILTER (exact): both dialects need `|` — a markdown row is `|…|` and a
    # bare row must split into >=2 `|` cells — so no `|` means no table.
    [[ "$text" == *"|"* ]] || return 1
    local _line _saw_rule=0 _saw_row=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ "${_line}" != *[![:space:]]* ]] && continue
        if _pt_is_rule "$_line" && [[ "$_line" == *"|"* ]]; then _saw_rule=1
        elif _pt_is_row "$_line"; then _saw_row=1; fi
    done
    if [[ $_saw_rule -eq 1 && $_saw_row -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    # No markdown rule — try the bare ` a | b | c ` dialect (strict shape check).
    if _pt_bare_shape "$text"; then
        _STRATEGY_CONFIDENCE=80
        _STRATEGY_CONFIDENCE_REASON="bare pipe table (a | b rows, uniform cells, no rule)"
        return 0
    fi
    return 1
}

# Extract a bare pipe table: first line is the header — unless one of its
# cells is digit-leading (`CPU1 Temp | 42 degrees C | ok`: a headerless sensor
# list where every line is data), in which case synthesize A,B,C… names.
_pt_extract_bare () {
    local text="$1" result="" entry=0 _line
    local col_names=() have_header=0 _c name i val first=1 _hl=0
    _PT_HROWS=()
    _pt_term_shape "$text"
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ "${_line}" != *[![:space:]]* ]] && continue
        _pt_is_rule "$_line" && continue
        [[ $entry -ge 1 && "$_line" != *"|"* ]] && _fr_is_footer "$_line" && continue
        _pt_trim "$_line"; _line="$_PT_TRIM"
        [[ $_PT_TERM -eq 1 ]] && _line="${_line%|}"
        _pt_split_bare "$_line"
        if [[ $first -eq 1 ]]; then
            first=0
            local _hl=0
            for _c in "${_PT_CELLS[@]}"; do [[ "$_c" == [0-9]* ]] && { _hl=1; break; }; done
            if [[ $_hl -eq 1 ]]; then
                for ((i = 0; i < ${#_PT_CELLS[@]}; i++)); do
                    col_names+=("$(_col_letter $((i + 1)))")
                done
                have_header=1
                # fall through: this first line is DATA, emit it below
            fi
        fi
        if [[ $have_header -eq 0 ]]; then
            for _c in "${_PT_CELLS[@]}"; do
                name="$_c"; name="${name//./}"; name="${name// /_}"
                while [[ "$name" == *__* ]]; do name="${name//__/_}"; done
                name="${name#_}"; name="${name%_}"
                [[ -z "$name" ]] && name="$(_col_letter $((${#col_names[@]} + 1)))"
                col_names+=("$name")
            done
            have_header=1; continue
        fi
        entry=$((entry + 1))
        if [[ $_hl -eq 1 ]]; then
            # headerless: hold the row, names are settled after the last one
            local _row="" _sep=$'\x1f'
            for ((i = 0; i < ${#col_names[@]}; i++)); do _row+="${_PT_CELLS[$i]:-}${_sep}"; done
            _PT_HROWS+=("$_row")
            continue
        fi
        for ((i = 0; i < ${#col_names[@]}; i++)); do
            val="${_PT_CELLS[$i]:-}"
            [[ -z "$val" ]] && continue
            result+="entry${entry}.${col_names[$i]} ${val}"$'\n'
        done
    done
    [[ ${_hl:-0} -eq 1 ]] && result+="$(_pt_headerless_kv "${col_names[@]}")"$'\n'
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}

# A headerless table's letter-named column whose every cell is `key=value`
# names itself. ReFrame 3.x's perflog is the case in point:
#
#   2026-11-10T17:41:28|reframe 3.12.0|fio_check @sys:part+env|jobid=32426|write_bw=826.0|ref=150 (l=-0.2, u=null)|MiB/s
#
# One key in every cell (`jobid=`, `ref=`): the key becomes the column name and
# the cells keep only their values. Several keys (`write_bw=`, `write_iops=`:
# one row per measured variable): the column splits into `<col>_key` and
# `<col>_value`. A column with any cell that is not `key=value`, or a table of
# fewer than two rows, keeps its letter. Reads _PT_HROWS (rows of cells joined
# by \x1f); echoes the `entryN.col value` lines.
_pt_headerless_kv () {
    local names=("$@") ncol=$# i r cell key out="" nrows=${#_PT_HROWS[@]}
    local -a mode=() kname=() _cells=()
    local _sep=$'\x1f' _re='^([A-Za-z_][A-Za-z0-9_.-]*)=(.*)$'
    for ((i = 0; i < ncol; i++)); do
        mode[i]=0; kname[i]=""
        [[ $nrows -ge 2 ]] || continue
        local first="" same=1 any=0 ok=1
        for ((r = 0; r < nrows; r++)); do
            IFS="$_sep" read -r -a _cells <<< "${_PT_HROWS[$r]}"
            cell="${_cells[$i]:-}"
            [[ -z "$cell" ]] && continue
            [[ "$cell" =~ $_re ]] || { ok=0; break; }
            key="${BASH_REMATCH[1]}"; any=1
            if [[ -z "$first" ]]; then first="$key"; elif [[ "$key" != "$first" ]]; then same=0; fi
        done
        [[ $ok -eq 1 && $any -eq 1 ]] || continue
        if [[ $same -eq 1 ]]; then mode[i]=1; kname[i]="$first"; else mode[i]=2; fi
    done
    for ((r = 0; r < nrows; r++)); do
        IFS="$_sep" read -r -a _cells <<< "${_PT_HROWS[$r]}"
        for ((i = 0; i < ncol; i++)); do
            cell="${_cells[$i]:-}"
            [[ -z "$cell" ]] && continue
            case "${mode[i]}" in
                1) [[ "$cell" =~ $_re ]]; [[ -n "${BASH_REMATCH[2]}" ]] &&
                       out+="entry$((r + 1)).${kname[i]} ${BASH_REMATCH[2]}"$'\n' ;;
                2) [[ "$cell" =~ $_re ]]
                   out+="entry$((r + 1)).${names[i]}_key ${BASH_REMATCH[1]}"$'\n'
                   [[ -n "${BASH_REMATCH[2]}" ]] &&
                       out+="entry$((r + 1)).${names[i]}_value ${BASH_REMATCH[2]}"$'\n' ;;
                *) out+="entry$((r + 1)).${names[i]} ${cell}"$'\n' ;;
            esac
        done
    done
    printf '%s' "$out"
}

strategy_extract () {
    local text="$1" result="" entry=0 _line
    # Which dialect won detection? Re-derive it EXACTLY as strategy_detect
    # does (detect's globals don't survive into this subshell): markdown needs
    # a `|---|` rule AND a `| … |` row. Keying on the rule alone sent a bare
    # table drawn with `---|---` rules (nyc / istanbul coverage) down the
    # markdown path, which found no `| … |` row and extracted nothing — so the
    # default run fell back to text-lines while --multi, whose block split
    # drops the rule lines, parsed the same table.
    local _has_rule=0 _has_row=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ "${_line}" != *[![:space:]]* ]] && continue
        if _pt_is_rule "$_line" && [[ "$_line" == *"|"* ]]; then _has_rule=1
        elif _pt_is_row "$_line"; then _has_row=1; fi
    done
    _line=""
    if [[ $_has_rule -eq 0 || $_has_row -eq 0 ]]; then
        _pt_extract_bare "$text"
        return
    fi
    # modal cell count across non-rule pipe rows
    local counts=()
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        _pt_is_row "$_line" || continue
        _pt_is_rule "$_line" && continue
        _pt_split "$_line"; counts+=("${#_PT_CELLS[@]}")
    done
    _line=""
    [[ ${#counts[@]} -lt 2 ]] && return
    local modal=0 best=0
    _fr_modal "${counts[@]}"; modal=$_FR_MODE; best=$_FR_MODE_N
    [[ $modal -lt 1 ]] && return

    local col_names=() num_cols=0 have_header=0 _c name i val
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
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
    done
    _line=""
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
