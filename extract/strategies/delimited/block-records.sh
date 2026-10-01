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
            !kv && /^ *[A-Za-z][A-Za-z0-9_ -]*[:=]/ { kv = 1 }
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

    # Must have key: value or key=value patterns
    [[ "$text" =~ (^|$'\n')\ *[A-Za-z][A-Za-z0-9_\ -]*[:=] ]] || return 1
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
        function block(   i, l, k, v, c, j, nc, ne, ok) {
            if (nb == 0) return
            rec++
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
                if (substr(v, 1, 7) == "http://" || substr(v, 1, 8) == "https://" || substr(v, 1, 2) == "//") continue
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
        result+="$(_tech_kv_colon "$_block" "$_prefix")"$'\n'
        result+="$(_tech_kv_equals "$_block" "$_prefix")"$'\n'
    done

    echo "$result"
}
