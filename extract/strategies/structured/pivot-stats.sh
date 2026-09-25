#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: pivot-stats
## Description: Per-record labeled counter pivots (ip -s link RX:/TX: sub-tables) — one wide row per record
## Version: 1.0
## Priority: 39
## Sample: samples/pivot-stats/basic.txt

# The `ip -s link` shape — a record header, then LABELED PIVOT pairs where a
# label line names the counters and the NEXT line carries their values:
#
#   2: eth0: <BROADCAST,...> mtu 1500 qdisc mq state UP mode DEFAULT
#       link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff
#       RX: bytes  packets  errors  dropped  overrun  mcast
#       9928374011 8837422  0       12       0        4421
#       TX: bytes  packets  errors  dropped  carrier  collsns
#       5432109876 4321098  0       1        0        0
#
# This is a PIVOT, not a carry-down (grouped-rows' shape): the label line is the
# column header of the single value row that follows. The lossless wide tidy is
# ONE ROW PER RECORD with the label folded into the counter names:
# (name, mtu, qdisc, state, …, rx_bytes, rx_packets, …, tx_bytes, …).
# Record headers also yield generic `word value` pairs (mtu 1500, state UP);
# other attribute lines (link/ether, inet …) are per-record detail we skip.

# Pivot header: `LABEL:` + >=2 name tokens (letters/underscores, no digits).
# Sets _PS_LABEL (lowercased) and _PS_NAMES.
_ps_is_pivot_header () {
    local t="$1"
    _PS_LABEL=""; _PS_NAMES=()
    [[ "$t" =~ ^([A-Za-z][A-Za-z0-9_]*):[[:space:]]+(.+)$ ]] || return 1
    local _lab="${BASH_REMATCH[1]}" _rest="${BASH_REMATCH[2]}"
    local _nm=() _n
    { _fr_tok "$_rest"; _nm=("${_FR_TOK[@]}"); }
    [[ ${#_nm[@]} -ge 2 ]] || return 1
    for _n in "${_nm[@]}"; do
        [[ "$_n" =~ ^[A-Za-z][A-Za-z0-9_/-]*$ ]] || return 1
    done
    _PS_LABEL="$(printf '%s' "$_lab" | tr '[:upper:]' '[:lower:]')"
    _PS_NAMES=("${_nm[@]}")
    return 0
}

# Value row: same token count, every token numeric-ish.
_ps_is_values () {
    local t="$1" want="$2"
    _PS_VALS=()
    local _v=() _x
    { _fr_tok "$t"; _v=("${_FR_TOK[@]}"); }
    [[ ${#_v[@]} -eq $want ]] || return 1
    for _x in "${_v[@]}"; do
        [[ "$_x" =~ ^-?[0-9]+([.][0-9]+)?[KMGTkmgt]?$ ]] || return 1
    done
    _PS_VALS=("${_v[@]}")
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local _l _prev_hdr=0 _prev_n=0 pivots=0 records=0
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        local t="${_l#"${_l%%[![:space:]]*}"}"
        if [[ $_prev_hdr -eq 1 ]] && _ps_is_values "$t" "$_prev_n"; then
            pivots=$((pivots + 1)); _prev_hdr=0; continue
        fi
        _prev_hdr=0
        if _ps_is_pivot_header "$t"; then _prev_hdr=1; _prev_n=${#_PS_NAMES[@]}; continue; fi
        [[ "$_l" =~ ^[^[:space:]] ]] && records=$((records + 1))
    done
    # >=2 pivot pairs and at least one unindented record header
    [[ $pivots -ge 2 && $records -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=86
    _STRATEGY_CONFIDENCE_REASON="labeled counter pivots (header line + value line) under record headers"
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0
    local _l pend_label="" pend_names=()
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        local t="${_l#"${_l%%[![:space:]]*}"}"
        # pending pivot: does this line carry the values?
        if [[ -n "$pend_label" ]] && _ps_is_values "$t" "${#pend_names[@]}"; then
            local i
            for ((i = 0; i < ${#pend_names[@]}; i++)); do
                local _cn="${pend_names[$i]//\//_}"; _cn="${_cn//-/_}"
                result+="entry${entry}.${pend_label}_${_cn} ${_PS_VALS[$i]}"$'\n'
            done
            pend_label=""; pend_names=()
            continue
        fi
        pend_label=""; pend_names=()
        # record header: unindented line opens a new row
        if [[ "$_l" =~ ^[^[:space:]] ]]; then
            entry=$((entry + 1))
            # `N: name: rest` (ip link) -> name; else first token
            local _name="" _rest=""
            if [[ "$t" =~ ^[0-9]+:[[:space:]]+([^:[:space:]]+):[[:space:]]*(.*)$ ]]; then
                _name="${BASH_REMATCH[1]}"; _rest="${BASH_REMATCH[2]}"
            else
                _name="${t%%[[:space:]]*}"; _rest="${t#*[[:space:]]}"
            fi
            result+="entry${entry}.name ${_name}"$'\n'
            # generic `word value` pairs in the rest (mtu 1500, state UP …);
            # <FLAG,LISTS> and bare tokens are skipped
            local _rt=() _ri
            { _fr_tok "$_rest"; _rt=("${_FR_TOK[@]}"); }
            for ((_ri = 0; _ri + 1 < ${#_rt[@]}; _ri++)); do
                local _k="${_rt[$_ri]}" _v="${_rt[$((_ri + 1))]}"
                if [[ "$_k" =~ ^[a-z][a-z_]*$ && ! "$_v" =~ ^[\<] && "$_v" != *:* ]]; then
                    result+="entry${entry}.${_k} ${_v}"$'\n'
                    _ri=$((_ri + 1))
                fi
            done
            continue
        fi
        # indented: pivot header, or per-record detail we skip
        if [[ $entry -gt 0 ]] && _ps_is_pivot_header "$t"; then
            pend_label="$_PS_LABEL"; pend_names=("${_PS_NAMES[@]}")
        fi
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
