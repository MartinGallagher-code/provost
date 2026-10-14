#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: block-records
## Description: Split input on blank lines into records, extract key:value and key=value fields
## Version: 1.0
## Priority: 40
## Sample: samples/blank-line-records/basic.txt

# Merges blank-line-records and repeated-blocks. Detects either:
#   (a) 2+ blank lines separating blocks with key:value/key=value patterns, or
#   (b) 1+ blank line where the same field name appears in multiple blocks.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # Reject JSON-like input
    _is_json "$1" && return 1

    # Must have at least one blank line separating blocks
    local blank_count=0
    if (( ${#text} > _FR_BIG_BYTES )); then
        # BIG input: the blank-line count and the key:value / key=value
        # screen below in one awk pass (the screen is a per-line match: the
        # pattern cannot span a newline)
        local _brd_kv=0
        read -r blank_count _brd_kv < <(cat <<< "$text" | awk '
            $0 == "" { b++; next }
            !kv && /^ *[A-Za-z]([A-Za-z0-9_-]| [A-Za-z0-9_-])* *[:=]/ && !/^ *[A-Za-z][A-Za-z0-9_-]*:[^ \t].*  / { kv = 1 }
            END { printf "%d %d\n", b, kv }')
        [[ $blank_count -lt 1 ]] && return 1
        [[ $_brd_kv -eq 1 ]] || return 1
    else
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ -z "$_line" ]] && blank_count=$((blank_count + 1))
    done
    _line=""
    [[ $blank_count -lt 1 ]] && return 1

    # Must have key: value or key=value patterns. An unspaced `key:value`
    # line whose rest holds a 2+-space column gap is a TABLE ROW whose first
    # cell is a colon-joined name (`Assets:Checking     5432.10` — ledger
    # accounts), not a field; a vCard `FN:Marie Curie` still counts. A key's
    # words are single-spaced (padding may follow, `Version : 1.2`):
    # `Users        C:\Users` is a table row whose first cell is followed by a
    # column gap and a drive letter, not a key.
    # (the same two tests as the awk screen above, byte for byte)
    local _brd_l _brd_kv=0 _brd_re1='^ *[A-Za-z]([A-Za-z0-9_-]| [A-Za-z0-9_-])* *[:=]' _brd_re2=$'^ *[A-Za-z][A-Za-z0-9_-]*:[^ \t].*  '
    for _brd_l in "${_FR_LINES[@]}"; do
        [[ "$_brd_l" =~ $_brd_re1 ]] || continue
        [[ "$_brd_l" =~ $_brd_re2 ]] && continue
        _brd_kv=1; break
    done
    [[ $_brd_kv -eq 1 ]] || return 1
    fi

    # Condition (a): 2+ blank lines is sufficient
    if [[ $blank_count -ge 2 ]]; then
        return 0
    fi

    # Condition (b): same field name appears in 2+ blocks (repeated-blocks criterion)
    local _unique_names="" _total=0 _unique=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        if [[ "$_line" =~ ^[\ ]*([A-Za-z][A-Za-z0-9_\ -]*): ]]; then
            local _name="${BASH_REMATCH[1]}"
            while [[ "$_name" == " "* ]]; do _name="${_name# }"; done
            while [[ "$_name" == *" " ]]; do _name="${_name% }"; done
            _total=$((_total + 1))
            case "|${_unique_names}|" in
                *"|${_name}|"*) ;;
                *) _unique=$((_unique + 1)); _unique_names="${_unique_names}|${_name}" ;;
            esac
        fi
    done
    _line=""
    [[ $_total -gt $_unique && $_unique -ge 1 ]] && return 0

    # Also check for equals-delimited fields (key=value) from repeated-blocks patterns
    _unique_names="" _total=0 _unique=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        if [[ "$_line" =~ ^[\ ]*([A-Za-z][A-Za-z0-9_\ -]*)= ]]; then
            local _name="${BASH_REMATCH[1]}"
            while [[ "$_name" == " "* ]]; do _name="${_name# }"; done
            while [[ "$_name" == *" " ]]; do _name="${_name% }"; done
            _total=$((_total + 1))
            case "|${_unique_names}|" in
                *"|${_name}|"*) ;;
                *) _unique=$((_unique + 1)); _unique_names="${_unique_names}|${_name}" ;;
            esac
        fi
    done
    _line=""
    [[ $_total -gt $_unique && $_unique -ge 1 ]] && return 0

    return 1
}

# _strat_blockrec_extract_awk TEXT — strategy_extract for a BIG input in one
# awk pass, byte-identical to the loop below: _tech_split_blocks' blank-line
# blocks, then per block _tech_kv_colon and _tech_kv_equals (each captured by
# `$(…)`, so trailing newlines dropped and one added back). The bash loop
# re-copies the remaining text per block and forks twice per block — on a
# big input, quadratic and minutes long. Returns 3 (nothing printed) when the
# text holds a \001 byte (the bash block separator) or an over-long non-ASCII
# key (${#key} counts characters): the caller then runs the bash loop.
_strat_blockrec_extract_awk () {
    [[ "$1" == *$'\001'* ]] && return 3
    local _o
    _o="$(cat <<< "$1" | awk '
        function lead(s) { sub(/^ +/, "", s); if (substr(s, 1, 2) == "* ") s = substr(s, 3); return s }
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        # _tech_validate_key: 1 valid, 0 invalid, -1 needs bash (length in chars)
        function vkey(k) {
            if (k == "") return 0
            if (length(k) > 50) { if (k ~ /[^\001-\177]/) return -1; return 0 }
            if (k ~ /^[0-9]/) return 0
            return 1
        }
        function block(   i, l, k, v, c, j, nc, ne, ok, tt, si, sc, i0, c0, ci, cc) {
            if (nb == 0) return
            rec++
            # title line (see _strat_blockrec_title)
            tt = (B[1] !~ /^[ \t]/ && !index(B[1], ":") && !index(B[1], "="))
            # (non-ASCII: bash measures characters, awk bytes — bash path)
            if (tt && B[1] ~ /[^\001-\177]/) { bail = 1; exit 3 }
            tt = tt && B[1] ~ /[A-Za-z0-9]/
            ok = 0; si = 1; sc = 1; i0 = -1; c0 = -1
            for (i = 2; i <= nb && tt; i++) {
                if (!index(B[i], ":")) continue
                if (B[i] !~ /^[ \t]+[^ \t]/) { tt = 0; break }
                ok = 1
                match(B[i], /^[ \t]+/); ci = RLENGTH; cc = index(B[i], ":")
                if (substr(B[i], 1, cc) ~ /[^\001-\177]/) { bail = 1; exit 3 }
                if (i0 < 0) { i0 = ci; c0 = cc }
                if (ci != i0) si = 0
                if (cc != c0) sc = 0
            }
            if (!si && !sc) tt = 0
            if (tt && ok) { v = trim(B[1]); gsub(/[\t\r\n]/, " ", v); if (v != "") print "record" rec ".title " v }
            nc = 0
            for (i = 1; i <= nb; i++) {
                l = B[i]
                if (l == "" || !index(l, ":")) continue
                j = index(l, " = ")
                if (j && !index(substr(l, 1, j - 1), ":")) continue
                l = lead(l)
                c = index(l, ":"); k = substr(l, 1, c - 1)
                j = index(l, ": ")
                if (j) v = substr(l, j + 2); else v = substr(l, c + 1)
                ok = vkey(k); if (ok < 0) { bail = 1; exit 3 }; if (!ok) continue
                if (substr(v, 1, 2) == "//") continue
                k = trim(k); gsub(/ /, "_", k)
                v = trim(v); gsub(/[\t\r\n]/, " ", v)
                if (k == "" || v == "") continue
                print "record" rec "." k " " v; nc++
            }
            if (!nc) printf "\n"
            ne = 0
            for (i = 1; i <= nb; i++) {
                l = B[i]
                if (l == "" || !index(l, "=")) continue
                if (index(l, "==") || index(l, "+=") || index(l, "!=")) continue
                l = lead(l)
                c = index(l, "="); k = substr(l, 1, c - 1); v = substr(l, c + 1)
                ok = vkey(k); if (ok < 0) { bail = 1; exit 3 }; if (!ok) continue
                k = trim(k); gsub(/ /, "_", k)
                v = trim(v); gsub(/[\t\r\n]/, " ", v)
                if (k == "" || v == "") continue
                print "record" rec "." k " " v; ne++
            }
            if (!ne) printf "\n"
            nb = 0
        }
        $0 == "" { block(); next }
        { B[++nb] = $0 }
        END {
            if (bail) exit 3
            block()
            printf "\n"
        }' && printf .)" || return 3
    [[ "$_o" == *. ]] || return 3
    printf '%s' "${_o%.}"
    return 0
}

# _strat_blockrec_title BLOCK — 0 when the block opens with a TITLE line over
# indented fields (`nokogiri (1.16.2)` over `    Author: …`, resolvectl's
# `Cache` over `   Cache Hits: …`): an unindented first line with
# no `:` / `=` and a letter or digit, no unindented `:` line after it, at
# least one indented `:` line, and those lines a flat list (one indent, or
# one colon column). The title is the record's identity — kept as
# `title` (cleaned into _CLEANED) instead of being dropped as a non-field.
_strat_blockrec_title () {
    local _bt_first="${1%%$'\n'*}" _bt_rest _bt_l _bt_kv=0 _bt_ind _bt_pre
    local _bt_i0=-1 _bt_c0=-1 _bt_si=1 _bt_sc=1 _bt_ci _bt_cc
    [[ "$_bt_first" != [' 	']* && "$_bt_first" != *[:=]* && "$_bt_first" == *[A-Za-z0-9]* ]] || return 1
    [[ "$1" == *$'\n'* ]] || return 1
    _bt_rest="${1#*$'\n'}"
    while IFS= read -r _bt_l; do
        [[ "$_bt_l" == *:* ]] || continue
        [[ "$_bt_l" == [' 	']*[!' 	']* ]] || return 1
        _bt_kv=1
        _bt_ind="${_bt_l%%[!' 	']*}"; _bt_ci=${#_bt_ind}
        _bt_pre="${_bt_l%%:*}"; _bt_cc=$(( ${#_bt_pre} + 1 ))
        [[ $_bt_i0 -lt 0 ]] && { _bt_i0=$_bt_ci; _bt_c0=$_bt_cc; }
        [[ $_bt_ci -ne $_bt_i0 ]] && _bt_si=0
        [[ $_bt_cc -ne $_bt_c0 ]] && _bt_sc=0
    done <<< "$_bt_rest"
    [[ $_bt_kv -eq 1 ]] || return 1
    # a FLAT field list — every field line at one indent, or every colon in
    # one column (right-aligned labels) — not a nested report
    [[ $_bt_si -eq 1 || $_bt_sc -eq 1 ]] || return 1
    _clean_value "$_bt_first"
    [[ -n "$_CLEANED" ]]
}

strategy_extract () {
    local text="$1"
    if (( ${#text} > _FR_BIG_BYTES )); then
        local _brx_rc=0
        _strat_blockrec_extract_awk "$text" || _brx_rc=$?
        [[ $_brx_rc -eq 3 ]] || return $_brx_rc
    fi
    local result=""
    local record_num=0

    _tech_split_blocks "$text"

    local _remaining="$_TECH_BLOCKS"
    while [[ -n "$_remaining" ]]; do
        local _block="${_remaining%%$'\x01'*}"
        [[ "$_remaining" == *$'\x01'* ]] && _remaining="${_remaining#*$'\x01'}" || _remaining=""
        [[ -z "$_block" ]] && continue
        record_num=$((record_num + 1))
        local _prefix="record${record_num}"
        _strat_blockrec_title "$_block" && result+="${_prefix}.title ${_CLEANED}"$'\n'
        result+="$(_tech_kv_colon "$_block" "$_prefix")"$'\n'
        result+="$(_tech_kv_equals "$_block" "$_prefix")"$'\n'
    done

    echo "$result"
}
