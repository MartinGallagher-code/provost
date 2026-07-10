#!/bin/bash
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
# uses `,`. Mirrors the csv strategy: a consistent, high semicolon count across
# every non-blank line. If the first row is all-numeric there is no header
# (fio terse) — synthesise A,B,C… and keep it; otherwise the first row names
# the columns. Distinct from colons (single `key: value` per line) — this needs
# MANY `;` per line, so a lone legend line ("o - Other; r - Repeater; …") under
# a real table never triggers it.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="consistent high semicolon count across lines"
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1

    local nonblank=0 first_sc=0 consistent=0 _l _t
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        _t="${_l//[^;]/}"; local sc=${#_t}
        [[ $sc -lt 4 ]] && return 1                 # every line must be ;-dense
        if [[ $nonblank -eq 1 ]]; then first_sc=$sc; consistent=1
        else
            local d=$(( first_sc - sc )); [[ ${d#-} -le 1 ]] && consistent=$((consistent + 1))
        fi
        [[ $nonblank -ge 40 ]] && break
    done <<< "$text"

    [[ $nonblank -ge 1 ]] || return 1
    [[ $consistent -eq $nonblank ]] || return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"

    # Field names: the first row if it carries non-numeric labels, else synthetic.
    local header="" _nb=0
    local _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        _nb=$((_nb + 1)); [[ -z "$header" ]] && header="$_l"
    done <<< "$text"

    local hcells; hcells=(); IFS=';' read -ra hcells <<< "$header"
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
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        row=$((row + 1))
        [[ $row -eq 1 && $_headerless -eq 0 ]] && continue
        local values; values=(); IFS=';' read -ra values <<< "$line"
        rec=$((rec + 1))
        local j v name
        for ((j=0; j<${#headers[@]}; j++)); do
            name="${headers[$j]}"; v="${values[$j]:-}"
            v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            [[ -z "$name" || -z "$v" ]] && continue
            result+="entry${rec}.${name} ${v}"$'\n'
        done
    done <<< "$text"
    [[ $rec -gt 0 ]] && result+="total_entries ${rec}"$'\n'
    echo "$result"
}
