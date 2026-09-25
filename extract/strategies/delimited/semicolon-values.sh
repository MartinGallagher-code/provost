#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: semicolon-values
## Description: Semicolon-delimited records (fio --output-format=terse, European-locale CSV)
## Version: 1.0
## Priority: 13
## Sample: samples/semicolon-values/basic.txt

# Records delimited by `;` rather than `,`:
#
#   3;fio-3.36;randread;0;0;28221440;482104;123001;60001;...   (fio terse)
#   name;value;unit                                            (some exporters)
#
# fio's terse output is one `;`-delimited line of ~130 positional fields; other
# tools (European-locale CSV, some `--format` exporters) use `;` the way csv
# uses `,`. Mirrors the csv strategy: a consistent semicolon count across every
# non-blank line — counted QUOTE-AWARE (a `;` inside "…" is data, the
# European-CSV case: `Schraube;"1.234,56";"12; nachbestellen"`). Two bands:
#   * dense (top-level count >=4, ±1 across lines) — fio terse and friends;
#   * low (2-3) — accepted only when EVERY line has the IDENTICAL top-level
#     count and there are >=2 lines, so prose with stray semicolons
#     ("o - Other; r - Repeater; …", which varies line to line) and a lone
#     legend line never qualify.
# If the first row is all-numeric there is no header (fio terse) — synthesise
# A,B,C… and keep it; otherwise the first row names the columns.

# Split one line on TOP-LEVEL semicolons into _SSV_CELLS (quote-aware: a quote
# is structural only at field start; "" inside a quoted field is an escaped
# quote; structural quotes are consumed, leftover quotes are data). Also sets
# _SSV_N to the top-level separator count.
_strat_ssv_split () {
    local line="$1"
    local i c field="" inq=0 atstart=1 len=${#line}
    _SSV_CELLS=(); _SSV_N=0
    i=0
    while [[ $i -lt $len ]]; do
        c="${line:$i:1}"
        if [[ $inq -eq 1 ]]; then
            if [[ "$c" == '"' ]]; then
                if [[ "${line:$((i+1)):1}" == '"' ]]; then field+='"'; i=$((i+2)); continue; fi
                inq=0; i=$((i+1)); continue
            fi
            field+="$c"; i=$((i+1)); continue
        fi
        if [[ "$c" == '"' && $atstart -eq 1 ]]; then inq=1; atstart=0; i=$((i+1)); continue; fi
        if [[ "$c" == ';' ]]; then
            _SSV_CELLS+=("$field"); _SSV_N=$((_SSV_N + 1))
            field=""; atstart=1; i=$((i+1)); continue
        fi
        [[ "$c" != " " && "$c" != $'\t' ]] && atstart=0
        field+="$c"; i=$((i+1))
    done
    _SSV_CELLS+=("$field")
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="consistent semicolon count across lines (quote-aware)"
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1

    local nonblank=0 first_sc=0 dense=1 _l sc
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        nonblank=$((nonblank + 1))
        _strat_ssv_split "$_l"; sc=$_SSV_N
        [[ $sc -lt 2 ]] && return 1
        if [[ $nonblank -gt 1 ]]; then
            if [[ $first_sc -ge 4 && $sc -ge 4 ]]; then
                local d=$(( first_sc - sc )); [[ ${d#-} -le 1 ]] || return 1
            else
                [[ $sc -eq $first_sc ]] || return 1   # low band: exact match only
            fi
        else
            first_sc=$sc
        fi
        [[ $sc -lt 4 ]] && dense=0
        [[ $nonblank -ge 40 ]] && break
    done

    [[ $nonblank -ge 1 ]] || return 1
    # a single low-density line is not enough signal (a lone prose line with
    # two semicolons); the dense band keeps single-line acceptance (fio terse)
    [[ $dense -eq 0 && $nonblank -lt 2 ]] && return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"

    # Field names: the first row if it carries non-numeric labels, else synthetic.
    local header="" _nb=0
    local _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        _nb=$((_nb + 1)); [[ -z "$header" ]] && header="$_l"
    done

    local hcells; _strat_ssv_split "$header"; hcells=("${_SSV_CELLS[@]}")
    # A single line is always one record (no header can exist without data); a
    # multi-line block is headerless only when its first row is all-numeric.
    local _headerless=1 _hc
    if [[ $_nb -gt 1 ]]; then
        for _hc in "${hcells[@]}"; do
            _hc="${_hc#"${_hc%%[![:space:]]*}"}"; _hc="${_hc%"${_hc##*[![:space:]]}"}"
            [[ -z "$_hc" || "$_hc" =~ ^-?[0-9]+([.][0-9]+)?%?$ ]] || { _headerless=0; break; }
        done
    fi

    local headers=() _k
    if [[ $_headerless -eq 1 ]]; then
        for ((_k=1; _k<=${#hcells[@]}; _k++)); do headers+=("$(_col_letter "$_k")"); done
    else
        for _hc in "${hcells[@]}"; do
            _hc="${_hc#"${_hc%%[![:space:]]*}"}"; _hc="${_hc%"${_hc##*[![:space:]]}"}"
            _hc="${_hc// /_}"; _hc="${_hc//./_}"; _hc="${_hc#_}"; _hc="${_hc%_}"
            [[ -z "$_hc" ]] && _hc="$(_col_letter $((${#headers[@]} + 1)))"
            headers+=("$_hc")
        done
    fi

    local result="" rec=0 row=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        row=$((row + 1))
        [[ $row -eq 1 && $_headerless -eq 0 ]] && continue
        local values; _strat_ssv_split "$line"; values=("${_SSV_CELLS[@]}")
        rec=$((rec + 1))
        local j v name
        for ((j=0; j<${#headers[@]}; j++)); do
            name="${headers[$j]}"; v="${values[$j]:-}"
            v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            [[ -z "$name" || -z "$v" ]] && continue
            result+="entry${rec}.${name} ${v}"$'\n'
        done
    done
    [[ $rec -gt 0 ]] && result+="total_entries ${rec}"$'\n'
    echo "$result"
}
