#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: vertical-line
## Description: Extract data from tables with separator lines (---, ===, etc.)
## Version: 1.1
## Priority: 45
## Sample: samples/vertical-line/benchmark.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Apply if input contains a separator line (--- or === repeated)
    [[ "$text" =~ (^|$'\n')[-=]{3,} ]] || return 1

    # The FIRST separator (the one extract splits under) must be a pure RULE
    # — dashes / equals, optionally broken by blanks, `+` or `|`. A TITLED
    # rule (`==== FAILURES ====`, `---- tests::x stdout ----`) is a section
    # banner in a test-runner or build report, not the underline of a column
    # header: reading the line above it as a header cut prose at fixed
    # character columns (pytest's `slowest durations` lines).
    local _vr_l
    _fr_lines "$text"
    for _vr_l in "${_FR_LINES[@]}"; do
        if [[ "$_vr_l" =~ ^[-=]{3,} ]]; then
            [[ "$_vr_l" =~ ^[-=+|[:space:]]+$ ]] || return 1
            break
        fi
    done

    # Decline a `label: value` key/value block that merely carries a `===`/`---`
    # banner (aureport --summary, `duplicity collection-status`). vertical-line
    # would split the banner's title line into positional columns and shred the
    # values; the `colons` parser tidies these to one field per label. Examine the
    # lines below the FIRST separator (the data region) — if most are `label: value`,
    # defer.
    local seen_sep=0 nb=0 kv=0 _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        if [[ $seen_sep -eq 0 ]]; then
            [[ "$_l" =~ ^[-=]{3,} ]] && seen_sep=1
            continue
        fi
        [[ "${_l}" != *[![:space:]]* ]] && continue
        nb=$((nb + 1))
        [[ "$_l" =~ ^[[:space:]]*[A-Za-z][^:]*:[[:space:]] ]] && kv=$((kv + 1))
    done
    [[ $nb -ge 2 && $(( kv * 100 / nb )) -ge $(( 60 + ${_FR_SLACK:-0} )) ]] && return 1

    # A header (the non-blank line above the first separator) that repeats a
    # column name is a GROUPED header (`zpool iostat`: `read write read write`
    # under `operations  bandwidth`). Cells are keyed by header name here, so
    # the repeat silently overwrote the first group's values — decline and
    # leave it to aligned-columns' two-line-header path, which qualifies them.
    # Only when the group row is the block's FIRST line (header on line 2):
    # that is the two-line-header shape aligned-columns can take over; behind
    # a preamble (repquota) this parser's lossy read is still the best one.
    local _vh_prev="" _vh_l _vh_t _vh_n=0
    for _vh_l in "${_FR_LINES[@]}"; do
        if [[ "$_vh_l" =~ ^[-=]{3,} ]]; then
            if [[ -n "$_vh_prev" && $_vh_n -eq 2 ]]; then
                local -A _vh_seen=()
                _fr_tok "$_vh_prev"
                for _vh_t in "${_FR_TOK[@]}"; do
                    [[ "$_vh_t" == *[A-Za-z0-9]* ]] || continue
                    [[ -n "${_vh_seen[$_vh_t]:-}" ]] && return 1
                    _vh_seen[$_vh_t]=1
                done
            fi
            break
        fi
        [[ "${_vh_l}" == *[![:space:]]* ]] && { _vh_prev="$_vh_l"; _vh_n=$((_vh_n + 1)); }
    done

    # The column cut points are the MIDPOINTS of the header's inter-label
    # gaps. When a data row has a non-blank character on BOTH sides of a cut,
    # the split would slice a value in two (pytest-cov's left-aligned
    # `src/parser.py` under `Name` cut at `src/parser.p|y`; scylla's
    # `10.0.1.|1`) — this table is not aligned to its header the way this
    # parser assumes, so decline and let the token/segment parsers read it.
    local _vc_sep=-1 _vc_i _vc_hdr="" _vc_n=${#_FR_LINES[@]}
    for ((_vc_i = 0; _vc_i < _vc_n; _vc_i++)); do
        [[ "${_FR_LINES[$_vc_i]}" =~ ^[-=]{3,} ]] && { _vc_sep=$_vc_i; break; }
    done
    if [[ $_vc_sep -ge 1 ]]; then
        _vc_hdr="${_FR_LINES[$((_vc_sep - 1))]}"
        # A "header" opening with a VALUE (`12M   ./etc` above a `====  ====`
        # totals rule) is the table's last data row, not its header — when
        # the rule is a per-column UNDERLINE (gapped runs). A single unbroken
        # rule under value rows (7z's summary split) is left as it was.
        [[ "$_vc_hdr" =~ ^[[:space:]]*[0-9] && "${_FR_LINES[$_vc_sep]}" =~ ^[-=]+[[:space:]]+[-=]+ ]] && return 1
        local _vc_cuts=() _vc_j _vc_in=0 _vc_pe=-1 _vc_c
        for ((_vc_j = 0; _vc_j < ${#_vc_hdr}; _vc_j++)); do
            _vc_c="${_vc_hdr:$_vc_j:1}"
            if [[ "$_vc_c" != " " ]]; then
                if [[ $_vc_in -eq 0 ]]; then
                    [[ $_vc_pe -ge 0 ]] && _vc_cuts+=($(( (_vc_pe + _vc_j + 1) / 2 )))
                    _vc_in=1
                fi
            else
                [[ $_vc_in -eq 1 ]] && { _vc_pe=$((_vc_j - 1)); _vc_in=0; }
            fi
        done
        # Conservative: only a header of single-word labels spaced >= 2 apart
        # (no repeated label), and a cut in at least half the rows.
        local _vc_clean=1 _vc_ht _vc_t2
        local -A _vc_seen=()
        [[ "$_vc_hdr" =~ [^[:space:]]\ [^[:space:]] ]] && _vc_clean=0
        _fr_tok "$_vc_hdr"
        for _vc_t2 in "${_FR_TOK[@]}"; do
            [[ -n "${_vc_seen[$_vc_t2]:-}" ]] && { _vc_clean=0; break; }
            _vc_seen[$_vc_t2]=1
        done
        local _vc_l _vc_k _vc_b _vc_rows=0 _vc_cutrows=0
        for ((_vc_i = _vc_sep + 1; _vc_clean == 1 && _vc_i < _vc_n && _vc_rows < 40; _vc_i++)); do
            _vc_l="${_FR_LINES[$_vc_i]}"
            [[ -z "$_vc_l" || "$_vc_l" =~ ^[-=]{3,} ]] && continue
            _vc_rows=$((_vc_rows + 1))
            for _vc_b in "${_vc_cuts[@]}"; do
                [[ $_vc_b -ge 1 && $_vc_b -lt ${#_vc_l} ]] || continue
                if [[ "${_vc_l:$((_vc_b - 1)):1}" != " " && "${_vc_l:$_vc_b:1}" != " " ]]; then
                    _vc_cutrows=$((_vc_cutrows + 1)); break
                fi
            done
        done
        [[ $_vc_clean -eq 1 && $_vc_rows -ge 1 && $(( _vc_cutrows * 2 )) -ge $_vc_rows ]] && return 1
    fi

    # Audit-report shape (aureport): a `# col col …` header line adjacent to
    # a `===` rule. aligned-columns strips that chrome and reads the real
    # header; splitting on the rule here would shred it.
    local _prev="" _cur
    _fr_lines "$text"
    for _cur in "${_FR_LINES[@]}"; do
        if [[ "$_cur" == "# "* && "$_prev" =~ ^[-=]{3,} ]] || \
           [[ "$_cur" =~ ^[-=]{3,} && "$_prev" == "# "* ]]; then
            return 1
        fi
        _prev="$_cur"
    done
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
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        _line_num=$((_line_num + 1))
        [[ $_line_num -le $separator_line_num ]] && continue
        [[ -z "$_line" ]] && continue
        if [[ -z "$data_lines" ]]; then
            data_lines="$_line"
        else
            data_lines+=$'\n'"$_line"
        fi
    done
    _line=""
    [[ -z "$data_lines" ]] && return

    # For each data row, extract values using computed column boundaries and emit
    # an indexed record group (entry<N>.<column>) so the tidy melt renders one row
    # per data line instead of welding every cell into one wide record.
    local result=""
    local entry=0
    _fr_lines "$data_lines"
    for row in "${_FR_LINES[@]}"; do
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
    done

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
