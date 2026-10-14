#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: tsv
## Description: Extract field names and values from TSV files (tab-delimited with header row)
## Version: 2.1
## Priority: 14
## Sample: samples/tsv/basic.tsv

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Must have at least 2 lines
    local line_count=0
    while IFS= read -r _line; do
        line_count=$((line_count + 1))
    done <<< "$text"
    [[ $line_count -lt 2 ]] && return 1

    # First line must contain a NON-LEADING tab: a tab at the start of the
    # line is indentation (ldd's tab-indented mapping lines), not an empty
    # first cell — real TSV delimits between values.
    local first_line=""
    IFS= read -r first_line <<< "$text"
    local _fl_stripped="${first_line#"${first_line%%[!$'\t']*}"}"
    [[ "$_fl_stripped" != *"	"* ]] && return 1

    # Tab count should be consistent between header and first data row
    local header_tabs=0 data_tabs=0
    local _tmp="$first_line"
    while [[ "$_tmp" == *"	"* ]]; do
        header_tabs=$((header_tabs + 1))
        _tmp="${_tmp#*	}"
    done

    # Get second line
    local _line_num=0 second_line=""
    while IFS= read -r _line; do
        _line_num=$((_line_num + 1))
        if [[ $_line_num -eq 2 ]]; then
            second_line="$_line"
            break
        fi
    done <<< "$text"

    _tmp="$second_line"
    while [[ "$_tmp" == *"	"* ]]; do
        data_tabs=$((data_tabs + 1))
        _tmp="${_tmp#*	}"
    done

    local diff=$(( header_tabs - data_tabs ))
    [[ ${diff#-} -le 1 ]] && return 0
    return 1
}

# Split one TSV line into _TSV_FIELDS, QUOTE-AWARE (the csv treatment with a
# tab delimiter): a '"' is structural only at FIELD START — it protects any
# tabs inside the field (`"a<TAB>b"` is ONE cell, not two) and is consumed;
# a mid-field quote is literal data. A protected tab becomes a single space in
# the emitted value — the tidy output is itself TSV, so a literal tab inside a
# cell would shear every column after it.
#
# EMPTY FIELDS. Two kinds of input put two tabs in a row, and they need
# opposite treatment:
#  * genuine tab-delimited DATA, where `4<TAB><TAB>6` is a row whose middle
#    cell is empty — dropping it shifts `6` left under the wrong header and
#    loses the last column;
#  * tab-PADDED display output (ldd's leading tab, proc-cpuinfo's
#    `flags<TAB><TAB>: …`), where the extra tabs are alignment, and keeping
#    them as cells would shift every later column's name and orphan values
#    into phantom columns.
# _TSV_KEEP_EMPTY selects the mode (1 = keep empty cells, 0 = a run of tabs is
# one separator and leading tabs are stripped). strategy_extract decides it
# once per input with _strat_tsv_choose_mode.
_TSV_KEEP_EMPTY=0
_tsv_split () {
    local line="$1"
    local field="" i c in_q=0 n=${#line}
    _TSV_FIELDS=()
    if [[ $_TSV_KEEP_EMPTY -eq 1 ]]; then
        for ((i = 0; i < n; i++)); do
            c="${line:$i:1}"
            if [[ $in_q -eq 1 ]]; then
                if [[ "$c" == '"' ]]; then in_q=0
                elif [[ "$c" == '	' ]]; then field+=' '
                else field+="$c"; fi
            elif [[ "$c" == '"' && -z "$field" ]]; then
                in_q=1
            elif [[ "$c" == '	' ]]; then
                _TSV_FIELDS+=("$field")
                field=""
            else
                field+="$c"
            fi
        done
        _TSV_FIELDS+=("$field")
        return 0
    fi
    for ((i = 0; i < n; i++)); do
        c="${line:$i:1}"
        if [[ $in_q -eq 1 ]]; then
            if [[ "$c" == '"' ]]; then in_q=0
            elif [[ "$c" == '	' ]]; then field+=' '
            else field+="$c"; fi
        elif [[ "$c" == '"' && -z "$field" ]]; then
            in_q=1
        elif [[ "$c" == '	' ]]; then
            [[ -n "$field" ]] && _TSV_FIELDS+=("$field")
            field=""
        else
            field+="$c"
        fi
    done
    [[ -n "$field" ]] && _TSV_FIELDS+=("$field")
}

# Decide _TSV_KEEP_EMPTY for the whole input. Empty cells are KEPT (genuine
# TSV) unless the input is evidently tab-padded display output:
#  * some column is empty on EVERY line, header included — a pure padding
#    column (a leading tab on every line, a doubled tab in the same place
#    everywhere) carries no data; or
#  * collapsing tab runs makes MORE lines agree with the header's width than
#    keeping them does — the column count is only consistent after collapsing
#    (proc-cpuinfo: `processor<TAB>: 0` vs `flags<TAB><TAB>: …`).
# Input with no empty cell at all is unaffected either way (fast path).
_strat_tsv_choose_mode () {
    local text="$1" l
    _TSV_KEEP_EMPTY=0
    local _nl=$'\n'
    # Fast path: no doubled tab, no leading or trailing tab -> no empty cell.
    [[ "$text" == *$'\t\t'* || "$text" == $'\t'* || "$text" == *"${_nl}"$'\t'* \
       || "$text" == *$'\t' || "$text" == *$'\t'"${_nl}"* ]] || return 0
    local -a keep_n=() coll_n=() nonempty=()
    local nlines=0 j
    while IFS= read -r l; do
        [[ -z "$l" ]] && continue
        nlines=$((nlines + 1))
        _TSV_KEEP_EMPTY=1; _tsv_split "$l"
        keep_n+=("${#_TSV_FIELDS[@]}")
        for ((j = 0; j < ${#_TSV_FIELDS[@]}; j++)); do
            [[ -n "${_TSV_FIELDS[$j]}" ]] && nonempty[$j]=1
        done
        _TSV_KEEP_EMPTY=0; _tsv_split "$l"
        coll_n+=("${#_TSV_FIELDS[@]}")
    done <<< "$text"
    _TSV_KEEP_EMPTY=0
    [[ $nlines -ge 1 ]] || return 0
    # A padding column: empty on every line (header included).
    local maxw=0
    for j in "${keep_n[@]}"; do [[ $j -gt $maxw ]] && maxw=$j; done
    for ((j = 0; j < maxw; j++)); do
        [[ -n "${nonempty[$j]:-}" ]] || return 0
    done
    # Width agreement with the header (line 1) under each mode.
    local keep_ok=0 coll_ok=0 i
    for ((i = 0; i < nlines; i++)); do
        [[ ${keep_n[$i]} -eq ${keep_n[0]} ]] && keep_ok=$((keep_ok + 1))
        [[ ${coll_n[$i]} -eq ${coll_n[0]} ]] && coll_ok=$((coll_ok + 1))
    done
    [[ $coll_ok -gt $keep_ok ]] && return 0
    _TSV_KEEP_EMPTY=1
}

strategy_extract () {
    local text="$1"

    # Keep or collapse empty cells (see _tsv_split / _strat_tsv_choose_mode)
    _strat_tsv_choose_mode "$text"

    # Parse header row for field names
    local header=""
    IFS= read -r header <<< "$text"

    # Split header into fields on tabs (quote-aware — see _tsv_split)
    local headers; headers=()
    _tsv_split "$header"; headers=("${_TSV_FIELDS[@]}")

    # Headerless TSV: synthesise A,B,C… names and treat every line as a record
    # when row 1 is already DATA — so `du` output (size <tab> path) stays one row
    # per line instead of eating row 1 as a header. Trigger (long-standing): row
    # 1 bears a digit anywhere — a header of pure labels does not.
    local headerless=0 _hf
    for _hf in "${headers[@]}"; do [[ "$_hf" =~ [0-9] ]] && { headerless=1; break; }; done
    # …but a digit-BEARING row 1 can still be a genuine header whose LABELS embed
    # digits (`C1`, `C6`, `Avg_MHz`). Distinguish by comparing row 1 to the first
    # data row, column by column: if some column is a non-numeric label in row 1
    # yet a numeric value in row 2, row 1 is a header after all — keep it (so
    # turbostat -q's 20-wide table keeps every column name instead of collapsing
    # to A…T). This override only ever fires when row 1 already looked headerless,
    # so nothing that used a header before changes. Gated to >=3 columns: a
    # 2-column tsv is a key/value or pair LIST (`wg show` pubkey<tab>time,
    # colon-value KV dumps) where the value column legitimately mixes text and
    # numbers row to row — never a wide table whose header needs rescuing.
    if [[ $headerless -eq 1 && ${#headers[@]} -ge 3 ]]; then
        local _second="" _ln=0
        while IFS= read -r _hf; do _ln=$((_ln + 1)); [[ $_ln -eq 2 ]] && { _second="$_hf"; break; }; done <<< "$text"
        if [[ -n "$_second" ]]; then
            local -a _d2=(); _tsv_split "$_second"; _d2=("${_TSV_FIELDS[@]}")
            local _i _h _v
            for ((_i=0; _i<${#headers[@]}; _i++)); do
                _h="${headers[$_i]}"; _h="${_h#"${_h%%[![:space:]]*}"}"
                _v="${_d2[$_i]:-}"; _v="${_v#"${_v%%[![:space:]]*}"}"
                if [[ "$_h" != [0-9]* && "$_h" != -[0-9]* ]] \
                   && { [[ "$_v" == [0-9]* ]] || [[ "$_v" == -[0-9]* ]]; }; then
                    headerless=0; break
                fi
            done
        fi
        # Second rescue: row 1's fields form a NUMBERED SERIES — >=2 adjacent
        # labels with one shared alpha prefix and integer suffixes ascending by
        # 1 (`col1 col2 col3`, `q1 q2 q3 q4`). That's a header-labeling idiom;
        # a data row essentially never enumerates itself like that.
        if [[ $headerless -eq 1 ]]; then
            local _run=1 _prevp="" _prevn=-1 _p _num
            for _hf in "${headers[@]}"; do
                if [[ "$_hf" =~ ^([A-Za-z_]+)([0-9]+)$ ]]; then
                    _p="${BASH_REMATCH[1]}"; _num="${BASH_REMATCH[2]}"
                    if [[ "$_p" == "$_prevp" && "$_num" -eq $((_prevn + 1)) ]]; then
                        _run=$((_run + 1))
                        [[ $_run -ge 2 ]] && { headerless=0; break; }
                    else
                        _run=1
                    fi
                    _prevp="$_p"; _prevn="$_num"
                else
                    _run=1; _prevp=""; _prevn=-1
                fi
            done
        fi
    fi
    # Labels do not recur as values: a row-1 cell that the SAME column repeats
    # in 2+ later rows (`shopt` / `set -o`: `autocd<TAB>off` over more
    # `…<TAB>off` lines) makes row 1 the first record, not a header.
    if [[ $headerless -eq 0 ]]; then
        local -a _rv=(); local _rl _rk _rc _rj
        local -A _rrep=()
        _rk=0
        while IFS= read -r _rl; do
            _rk=$((_rk + 1)); [[ $_rk -eq 1 ]] && continue
            [[ "$_rl" == *[![:space:]]* ]] || continue
            _tsv_split "$_rl"; _rv=("${_TSV_FIELDS[@]}")
            for ((_rj = 0; _rj < ${#headers[@]}; _rj++)); do
                _rc="${headers[$_rj]}"; _rc="${_rc#"${_rc%%[![:space:]]*}"}"; _rc="${_rc%"${_rc##*[![:space:]]}"}"
                [[ -n "$_rc" ]] || continue
                local _rvv="${_rv[$_rj]:-}"; _rvv="${_rvv#"${_rvv%%[![:space:]]*}"}"; _rvv="${_rvv%"${_rvv##*[![:space:]]}"}"
                [[ "$_rvv" == "$_rc" ]] && _rrep[$_rj]=$(( ${_rrep[$_rj]:-0} + 1 ))
            done
            [[ $_rk -ge 41 ]] && break
        done <<< "$text"
        for _rj in "${!_rrep[@]}"; do [[ ${_rrep[$_rj]} -ge 2 ]] && { headerless=1; break; }; done
    fi
    if [[ $headerless -eq 1 ]]; then
        local _n=${#headers[@]} _i
        headers=()
        for ((_i = 1; _i <= _n; _i++)); do headers+=("$(_col_letter "$_i")"); done
    fi
    # Keep-empty mode: an EMPTY header cell over a data column (a matrix's
    # blank corner — nvidia-smi topo -m's row labels) is a nameless column,
    # not a column to drop; name it by position like any nameless column.
    if [[ $_TSV_KEEP_EMPTY -eq 1 ]]; then
        local _ei
        for ((_ei = 0; _ei < ${#headers[@]}; _ei++)); do
            [[ -z "${headers[$_ei]//[[:space:]\"]/}" ]] && headers[$_ei]="$(_col_letter $((_ei + 1)))"
        done
    fi

    # CELL-SPLIT pre-pass. Two shapes hide multiple fields inside ONE tab
    # cell, recognisable only across the whole column:
    #  * datetime-prefix (`Thu Jul 10 18:00:00 2026 a deploy` — at/atq):
    #    every row's cell opens with a full ctime-style stamp followed by a
    #    UNIFORM number of trailing tokens → stamp column + one column per
    #    trailing token.
    #  * constant multi-word prefix (`nice run-parts /etc/cron.daily` —
    #    anacrontab): every row shares the same >=2-token prefix with a
    #    non-empty remainder → prefix column + remainder column.
    local _cs_rows=() _cs_l _cs_rn=0
    while IFS= read -r _cs_l; do
        _cs_rn=$((_cs_rn + 1))
        [[ $_cs_rn -eq 1 && $headerless -eq 0 ]] && continue
        [[ -z "$_cs_l" ]] && continue
        _cs_rows+=("$_cs_l")
    done <<< "$text"
    local _dt_split=() _cp_split=() _cp_pref=() _dt_ntok=()
    local _dt_re='^([A-Z][a-z]{2}[[:space:]]+[A-Z][a-z]{2}[[:space:]]+[0-9]{1,2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+[0-9]{4})[[:space:]]+(.+)$'
    if [[ ${#_cs_rows[@]} -ge 2 ]]; then
        local _cs_j _cs_r
        for ((_cs_j = 0; _cs_j < ${#headers[@]}; _cs_j++)); do
            local _dt_all=1 _dt_n=-1 _cp_all=1 _cp_p=""
            for _cs_r in "${_cs_rows[@]}"; do
                _tsv_split "$_cs_r"
                local _cs_v="${_TSV_FIELDS[$_cs_j]:-}"
                if [[ "$_cs_v" =~ $_dt_re ]]; then
                    local _dt_rest=() ; read -ra _dt_rest <<< "${BASH_REMATCH[2]}"
                    [[ $_dt_n -lt 0 ]] && _dt_n=${#_dt_rest[@]}
                    [[ ${#_dt_rest[@]} -ne $_dt_n ]] && _dt_all=0
                else
                    _dt_all=0
                fi
                local _cp_tk=() ; read -ra _cp_tk <<< "$_cs_v"
                # The remainder must be ARGUMENT-shaped (a path, flag or
                # number: anacrontab's `/etc/cron.daily`) — a word remainder
                # means the cell is one multi-word LABEL ("number of
                # samples:" — bcftools) and must stay whole.
                if [[ ${#_cp_tk[@]} -ge 3 && "${_cp_tk[2]}" =~ ^[/~.0-9-] ]]; then
                    local _cp_this="${_cp_tk[0]} ${_cp_tk[1]}"
                    [[ -z "$_cp_p" ]] && _cp_p="$_cp_this"
                    [[ "$_cp_this" != "$_cp_p" ]] && _cp_all=0
                else
                    _cp_all=0
                fi
            done
            _dt_split[$_cs_j]=0; _cp_split[$_cs_j]=0; _cp_pref[$_cs_j]=""; _dt_ntok[$_cs_j]=0
            if [[ $_dt_all -eq 1 && $_dt_n -ge 1 ]]; then
                _dt_split[$_cs_j]=1; _dt_ntok[$_cs_j]=$_dt_n
            elif [[ $_cp_all -eq 1 && -n "$_cp_p" ]]; then
                _cp_split[$_cs_j]=1; _cp_pref[$_cs_j]="$_cp_p"
            fi
        done
    fi

    # Process each data row as an indexed record group (entry<N>.<column>) so the
    # capture tidy melt renders one row per record — rather than welding every
    # row's cells into a single wide record with duplicate column names.
    local result=""
    local row_num=0
    local rec=0
    while IFS= read -r line; do
        row_num=$((row_num + 1))
        [[ $row_num -eq 1 && $headerless -eq 0 ]] && continue  # skip header
        [[ -z "$line" ]] && continue

        # Split on tabs (quote-aware — see _tsv_split)
        local values; values=()
        _tsv_split "$line"; values=("${_TSV_FIELDS[@]}")

        rec=$((rec + 1))
        local j
        for ((j=0; j<${#headers[@]}; j++)); do
            local name="${headers[$j]}"
            local value="${values[$j]:-}"
            if [[ "${_dt_split[$j]:-0}" -eq 1 && "$value" =~ $_dt_re ]]; then
                local _dt_stamp="${BASH_REMATCH[1]}" _dt_tail="${BASH_REMATCH[2]}"
                local _dt_tt=() _dt_k
                read -ra _dt_tt <<< "$_dt_tail"
                local _nm0="${name//\"}"; _nm0="${_nm0// /_}"; _nm0="${_nm0//./_}"
                result+="entry${rec}.${_nm0} ${_dt_stamp}"$'\n'
                for ((_dt_k = 0; _dt_k < ${#_dt_tt[@]}; _dt_k++)); do
                    result+="entry${rec}.${_nm0}_$(_col_letter $((_dt_k + 2))) ${_dt_tt[$_dt_k]}"$'\n'
                done
                continue
            fi
            if [[ "${_cp_split[$j]:-0}" -eq 1 ]]; then
                local _cp_rest="${value#"${_cp_pref[$j]}"}"
                _cp_rest="${_cp_rest# }"
                local _nm1="${name//\"}"; _nm1="${_nm1// /_}"; _nm1="${_nm1//./_}"
                result+="entry${rec}.${_nm1} ${_cp_pref[$j]}"$'\n'
                [[ -n "$_cp_rest" ]] && result+="entry${rec}.${_nm1}_b ${_cp_rest}"$'\n'
                continue
            fi
            # Clean up name and value: replace spaces with underscores, remove quotes
            name="${name//\"}"
            name="${name// /_}"
            name="${name#_}"
            name="${name%_}"
            name="${name//./_}"   # '.' would break the tidy melt's group key split
            value="${value//\"}"
            [[ -z "$name" ]] && continue
            if [[ -z "$value" ]]; then
                [[ $_TSV_KEEP_EMPTY -eq 1 ]] && result+="entry${rec}.${name} "$'\n'
                continue
            fi
            result+="entry${rec}.${name} ${value}"$'\n'
        done
    done <<< "$text"

    [[ $rec -gt 0 ]] && result+="total_entries ${rec}"$'\n'
    echo "$result"
}
