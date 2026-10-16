#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: fixed-width
## Description: Fixed-width column format with header/separator
## Version: 1.0
## Priority: 30
## Sample: samples/fixed-width/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # Reject JSON-like input
    _is_json "$1" && return 1

    # Decline `+---+` box tables — psql-table's box parser owns those.
    local _bxl
    _fr_lines "$text"
    for _bxl in "${_FR_LINES[@]}"; do
        [[ "$_bxl" == *"+"* && "$_bxl" == *"---"* ]] || continue
        [[ "$_bxl" =~ ^[[:space:]]*[-+[:space:]]+$ ]] && return 1
    done

    # Must have a separator line of dashes with gaps (scan line by line)
    # A header (the non-blank line just above the rule) that repeats a
    # column name is a GROUPED header — `zpool iostat`'s `read write read
    # write` under `operations  bandwidth` — and this parser keys cells by
    # header name, so the second `read` silently overwrote the first
    # (operations lost). Decline: aligned-columns' two-line-header path
    # qualifies the names (operations_read, bandwidth_read) and keeps them all.
    local _det_line _det_prev=""
    _fr_lines "$text"
    for _det_line in "${_FR_LINES[@]}"; do
        if _strat_fw_is_rule "$_det_line"; then
            if ! _strat_fw_old_rule "$_det_line"; then
                # An indented or `=` underline is taken only when it UNDERLINES
                # a header — a letter-bearing line not opening with a value (a
                # `====  ====` totals rule under the last data row is no
                # underline) — and the text holds ONE such table: a second
                # underline further down is a multi-section report, which
                # one header's columns would garble.
                [[ "$_det_prev" == *[A-Za-z]* ]] || return 1
                [[ "$_det_prev" =~ ^[[:space:]]*[0-9] ]] && return 1
                local _det_after=0 _det_l2
                for _det_l2 in "${_FR_LINES[@]}"; do
                    if [[ $_det_after -eq 1 ]] && _strat_fw_is_rule "$_det_l2"; then return 1; fi
                    [[ "$_det_l2" == "$_det_line" ]] && _det_after=1
                done
            fi
            if [[ -n "$_det_prev" ]]; then
                # (names as extract derives them: the header sliced at the
                # rule's dash runs — `min threads` / `max threads` are two
                # distinct cells, not a repeated `threads`)
                local -A _det_seen=()
                local _det_p _det_cs _det_ce _det_h _det_pos
                _det_pos="$(_strat_fw_find_columns "$_det_line")"
                local IFS='|'
                for _det_p in $_det_pos; do
                    _det_cs="${_det_p%%:*}"; _det_ce="${_det_p##*:}"
                    _det_h="${_det_prev:$_det_cs:$((_det_ce - _det_cs))}"
                    _det_h="${_det_h#"${_det_h%%[![:space:]]*}"}"
                    _det_h="${_det_h%"${_det_h##*[![:space:]]}"}"
                    [[ "$_det_h" == *[A-Za-z0-9]* ]] || continue
                    [[ -n "${_det_seen[$_det_h]:-}" ]] && return 1
                    _det_seen[$_det_h]=1
                done
            fi
            return 0
        fi
        [[ "${_det_line}" == *[![:space:]]* ]] && _det_prev="$_det_line"
    done

    return 1
}

# _strat_fw_is_rule LINE — a per-column UNDERLINE rule: two or more runs of
# dashes (or of `=`, Windows `tasklist` / `driverquery` / `schtasks`), each
# under one header label, set apart by spaces; it may be indented. (The
# original form, dash runs from column 0, is the `-` case; an unbroken rule
# names no columns and stays vertical-line's.)
_strat_fw_is_rule () {
    [[ "$1" =~ ^[-]+(\ +[-]+)+ ]] && return 0
    [[ "$1" =~ ^\ *(-+|=+)(\ +(-+|=+))+\ *$ ]]
}
# _strat_fw_old_rule LINE — the original shape (dash runs from column 0),
# which keeps the token-slicer fallback; the newer shapes are taken only
# through the gutter grid (see strategy_extract).
_strat_fw_old_rule () { [[ "$1" =~ ^[-]+(\ +[-]+)+ ]]; }

_strat_fw_find_columns () {
    # Given a separator line like "-------  --------  --------   -----"
    # return column start:end positions
    local sep_line="$1"
    local positions=""
    local i=0
    local len=${#sep_line}
    local in_dash=0
    local col_start=0

    while [[ $i -lt $len ]]; do
        local ch="${sep_line:$i:1}"
        if [[ "$ch" == "-" || "$ch" == "=" ]]; then
            if [[ $in_dash -eq 0 ]]; then
                col_start=$i
                in_dash=1
            fi
        else
            if [[ $in_dash -eq 1 ]]; then
                # End of a dash column
                if [[ -n "$positions" ]]; then
                    positions+="|"
                fi
                positions+="${col_start}:${i}"
                in_dash=0
            fi
        fi
        i=$((i + 1))
    done

    # Handle last column if line ends with dashes
    if [[ $in_dash -eq 1 ]]; then
        if [[ -n "$positions" ]]; then
            positions+="|"
        fi
        positions+="${col_start}:${i}"
    fi

    # A column OWNS the gap up to the next column's start: a dash run only
    # marks where a column begins, and slicing at the run's own END truncates
    # any value wider than its run (heroku's `heroku-postgresql:standard-0`
    # under a 24-dash run lost its tail into the next column). The last
    # column runs to end-of-line.
    local stretched="" seg next_start
    local -a segs=()
    local IFS='|'
    { _fr_tok "$positions"; segs=("${_FR_TOK[@]}"); }
    local si
    for ((si = 0; si < ${#segs[@]}; si++)); do
        seg="${segs[$si]}"
        [[ -z "$seg" ]] && continue
        if [[ $((si + 1)) -lt ${#segs[@]} ]]; then
            next_start="${segs[$((si + 1))]%%:*}"
            seg="${seg%%:*}:$((next_start - 1))"
        else
            seg="${seg%%:*}:100000"
        fi
        [[ -n "$stretched" ]] && stretched+="|"
        stretched+="$seg"
    done

    echo "$stretched"
}

strategy_extract () {
    local text="$1"
    local result=""

    # GUTTER GRID first (lib/_helpers.sh _FR_AWK_GRID): the rule's runs name
    # the columns, and the data's own alignment gives each column's extent —
    # a right-aligned number wider than its run (`102400` under a five-dash
    # `PM(K)`), a date that starts left of its label (`10/14/2026   9:03 AM`
    # under `LastWriteTime`), an empty cell, all land in their column. The
    # rows are the ones the slicer below reads (later rules dropped), minus a
    # trailing result-set footer (`(5 rows affected)` — _FR_FOOTER_RE). When
    # the grid withdraws, the slicer runs as before.
    local _fg_l _fg_i _fg_r=-1 _fg_h=-1 _fg_out _fg_cut=-1
    local -a _fg_rows=() _fg_at=()
    _fr_lines "$text"
    for ((_fg_i = 0; _fg_i < ${#_FR_LINES[@]}; _fg_i++)); do
        _fg_l="${_FR_LINES[$_fg_i]}"
        if [[ $_fg_r -lt 0 ]]; then
            if _strat_fw_is_rule "$_fg_l"; then _fg_r=$_fg_i; continue; fi
            [[ "$_fg_l" == *[![:space:]]* ]] && _fg_h=$_fg_i
            continue
        fi
        [[ "$_fg_l" == *[![:space:]]* ]] || continue
        [[ "$_fg_l" =~ ^[[:space:]]*(-+|=+)([[:space:]]+(-+|=+))*[[:space:]]*$ ]] && continue
        _fg_rows+=("$_fg_l"); _fg_at+=("$_fg_i")
    done
    # (the table ends at a result-set footer; the client's prompt or timing
    # line after it goes too — lib/_helpers.sh _fr_footer_cut)
    _FR_FC=("${_fg_rows[@]}"); _fr_footer_cut
    if [[ $_FR_FC_N -lt ${#_fg_rows[@]} ]]; then
        _fg_cut=${_fg_at[$_FR_FC_N]}
        _fg_rows=("${_fg_rows[@]:0:$_FR_FC_N}")
    fi
    # A header WRAPPED onto two lines (PowerShell's Format-Table: `Partition`
    # over `Style`) leaves the line above the rule naming only some of its
    # runs; the line directly above that one, naming the others, is the
    # first half of the labels — read as the grid's group row, whose words
    # prefix the names under them.
    if [[ $_fg_r -ge 1 && $_fg_h -ge 1 && $_fg_h -eq $((_fg_r - 1)) && ${#_fg_rows[@]} -ge 1 \
          && "${_FR_LINES[$((_fg_h - 1))]}" == *[![:space:]]* ]]; then
        local _fg_up="${_FR_LINES[$((_fg_h - 1))]}" _fg_runs _fg_hw
        _fr_tok "${_FR_LINES[$_fg_r]}"; _fg_runs=${#_FR_TOK[@]}
        _fr_tok "${_FR_LINES[$_fg_h]}"; _fg_hw=${#_FR_TOK[@]}
        _fr_tok "$_fg_up"
        if [[ $_fg_hw -lt $_fg_runs && ${#_FR_TOK[@]} -ge $_fg_runs ]]; then
            _fg_out="$(printf '%s\n' "$_fg_up" "${_FR_LINES[$_fg_h]}" "${_FR_LINES[$_fg_r]}" "${_fg_rows[@]}" | _fr_gutter_grid 2 1 row)"
            if [[ -n "$_fg_out" ]]; then echo "$_fg_out"; return 0; fi
        fi
    fi
    if [[ $_fg_r -ge 1 && $_fg_h -ge 0 && ${#_fg_rows[@]} -ge 1 ]]; then
        _fg_out="$(printf '%s\n' "${_FR_LINES[$_fg_h]}" "${_FR_LINES[$_fg_r]}" "${_fg_rows[@]}" | _fr_gutter_grid 1 1 row)"
        if [[ -n "$_fg_out" ]]; then echo "$_fg_out"; return 0; fi
    fi
    # (a newer rule shape has no slicer fallback: nothing, and the next
    # candidate reads the table)
    [[ $_fg_r -ge 0 ]] && ! _strat_fw_old_rule "${_FR_LINES[$_fg_r]}" && { echo ""; return 0; }

    # Find the separator line
    local sep_line=""
    local header_line=""
    local sep_line_num=0
    local line_num=0
    local prev_line=""

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if _strat_fw_is_rule "$line"; then
            sep_line="$line"
            sep_line_num=$line_num
            header_line="$prev_line"
            break
        fi
        prev_line="$line"
    done <<< "$text"

    [[ -z "$sep_line" ]] && return

    # Get column positions from separator
    local col_positions
    col_positions=$(_strat_fw_find_columns "$sep_line")

    # Parse column positions into arrays
    local col_starts=""
    local col_ends=""
    local num_cols=0
    local old_ifs="$IFS"
    IFS='|'
    local pos_entries
    { _fr_tok "$col_positions"; pos_entries=("${_FR_TOK[@]}"); }
    IFS="$old_ifs"

    local p
    for p in "${pos_entries[@]}"; do
        [[ -z "$p" ]] && continue
        local cs="${p%%:*}"
        local ce="${p##*:}"
        col_starts="${col_starts}${cs} "
        col_ends="${col_ends}${ce} "
        num_cols=$((num_cols + 1))
    done

    # Extract header names using column positions
    local headers=""
    local ci=0
    local starts_arr
    local ends_arr
    { _fr_tok "$col_starts"; starts_arr=("${_FR_TOK[@]}"); }
    { _fr_tok "$col_ends"; ends_arr=("${_FR_TOK[@]}"); }

    for ((ci=0; ci<num_cols; ci++)); do
        local cs=${starts_arr[$ci]}
        local ce=${ends_arr[$ci]}
        local clen=$((ce - cs))
        local hdr="${header_line:$cs:$clen}"
        # Trim whitespace and replace spaces with underscores
        while [[ "$hdr" == " "* ]]; do hdr="${hdr# }"; done
        while [[ "$hdr" == *" " ]]; do hdr="${hdr% }"; done
        hdr="${hdr// /_}"
        if [[ -n "$headers" ]]; then
            headers+=" "
        fi
        headers+="$hdr"
    done

    local headers_arr
    { _fr_tok "$headers"; headers_arr=("${_FR_TOK[@]}"); }

    # Extract data rows (lines after separator)
    local row_num=0
    local past_sep=0 _fw_li=-1
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _fw_li=$((_fw_li + 1))
        [[ $_fg_cut -ge 0 && $_fw_li -ge $_fg_cut ]] && break
        if [[ $past_sep -eq 0 ]]; then
            if _strat_fw_is_rule "$line"; then
                past_sep=1
            fi
            continue
        fi

        [[ -z "$line" ]] && continue
        # A later dash rule (strace -c's rule above its `total` row, a
        # closing rule) is table chrome, never a data row.
        [[ "$line" =~ ^[[:space:]]*--+([[:space:]]+--+)*[[:space:]]*$ ]] && continue
        row_num=$((row_num + 1))

        # SOFT boundaries with a per-row cursor. A tool's separator rule can be
        # NARROWER than its own data (heroku-addons' 24-dash Plan run under a
        # 28-char plan name), and slicing hard at the rule's grid cut values
        # mid-word and bled their tails into the next column. Instead: a
        # column ends where the rule says — unless a word is straddling the
        # cut, in which case the column keeps the whole word and the next
        # column starts after it.
        local _fw_cursor=0 _fw_len=${#line}
        for ((ci=0; ci<num_cols; ci++)); do
            local cs=${starts_arr[$ci]}
            local ce=${ends_arr[$ci]}
            local hdr="${headers_arr[$ci]}"
            local val

            [[ $cs -lt $_fw_cursor ]] && cs=$_fw_cursor
            if [[ $ci -eq $((num_cols - 1)) ]]; then
                ce=$_fw_len
            else
                # extend through a straddling word
                while [[ $ce -lt $_fw_len && "${line:$ce:1}" != " " && "${line:$((ce - 1)):1}" != " " ]]; do
                    ce=$((ce + 1))
                done
            fi
            val="${line:$cs:$((ce - cs))}"
            _fw_cursor=$ce

            # Trim edges; spaces inside the value are preserved (the engine keeps
            # everything after the first space as the value).
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            [[ -z "$val" ]] && continue

            result+="row${row_num}.${hdr} ${val}"$'\n'
        done
    done
    line=""

    echo "$result"
}
