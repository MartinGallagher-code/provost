#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: group-children
## Description: Unindented group lines over one level of indented child lines (apt-rdepends, ssh_config Host blocks, ip addr inet lines) -> one row per child or per group
## Version: 1.0
## Priority: 42
## Sample: samples/group-children/basic.txt

# A family of outputs prints an UNINDENTED group line and, beneath it, one
# level of INDENTED children that belong to it:
#
#   openssl                         Host web1
#     Depends: libc6 (>= 2.34)          HostName 203.0.113.10
#     Depends: libssl3 (>= 3.0.0)       User deploy
#   libc6                               Port 22
#     Depends: libgcc-s1            Host web2
#                                       HostName 203.0.113.11 …
#
# indented-hierarchy flattens these into ONE record of dotted paths (and
# drops repeated keys), so N groups collapse to a single row. The tidy shape
# carries the group down, in one of two modes decided by the children:
#
#   LONG — every child is `Label: value` under ONE label shared by the whole
#          input (apt-rdepends' `Depends` / `Reverse Depends`): one row per
#          child — group + <Label>.
#   WIDE — each child is `key value` / `key: value` with keys DISTINCT inside
#          its group and SHARED across groups (ssh_config's HostName/User/
#          Port, ip addr's inet/inet6): one row per group, a column per key.
#
# The group column is named by the group line's own first token when every
# group line is `<same-token> <one-token>` (ssh `Host web1` -> Host=web1),
# else `group` (a trailing `:` dropped).
#
# Detection is strict, so attribute blocks and real hierarchies keep their
# parsers: >= 2 groups, every group has >= 1 child, every child sits at the
# SAME indentation (one level, nothing deeper), no child before the first
# group, and the children fit LONG or WIDE exactly. LONG also requires group
# lines free of `: ` (they are bare names). Bare-member groups (`header:` over
# single tokens) are indented-colon-groups'; it outranks this by priority.

_gc_scan () {
    local text="$1" l ind="" n_g=0 n_c=0 cur_kids=0 bad=0
    _GC_GROUPS=() _GC_KIDS=() _GC_GOF=()
    _fr_lines "$text"
    for l in "${_FR_LINES[@]}"; do
        [[ "${l}" != *[![:space:]]* ]] && continue
        if [[ "$l" != [[:space:]]* ]]; then
            [[ $n_g -gt 0 && $cur_kids -eq 0 ]] && { bad=1; break; }
            _GC_GROUPS+=("$l"); n_g=$((n_g + 1)); cur_kids=0
            continue
        fi
        [[ $n_g -eq 0 ]] && { bad=1; break; }
        local li="${l%%[![:space:]]*}"
        if [[ -z "$ind" ]]; then ind="$li"
        elif [[ "$li" != "$ind" ]]; then bad=1; break; fi
        _GC_KIDS+=("${l#"$li"}"); _GC_GOF+=($((n_g - 1)))
        n_c=$((n_c + 1)); cur_kids=$((cur_kids + 1))
    done
    [[ $bad -eq 0 && $n_g -ge 2 && $cur_kids -ge 1 ]]
}

# Split a child into _GC_K / _GC_V: `Label: value` (label of words), `key =
# value`, else `key value` on the first whitespace. Returns 1 when no value.
_gc_kv () {
    local c="$1"
    _GC_COLON=0
    if [[ "$c" =~ ^([A-Za-z][A-Za-z0-9_.\ -]*):[[:space:]]+(.+)$ ]]; then
        _GC_K="${BASH_REMATCH[1]}"; _GC_V="${BASH_REMATCH[2]}"; _GC_COLON=1
        return 0
    fi
    # `key = value` (pw-cli properties) — the `=` is a separator
    if [[ "$c" =~ ^([^[:space:]=]+)[[:space:]]+=[[:space:]]+(.+)$ ]]; then
        _GC_K="${BASH_REMATCH[1]}"; _GC_V="${BASH_REMATCH[2]}"
        return 0
    fi
    if [[ "$c" =~ ^([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
        _GC_K="${BASH_REMATCH[1]}"; _GC_V="${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

_gc_mode () {
    _GC_MODE=""
    local i k nk=${#_GC_KIDS[@]}
    # LONG: one shared colon label over every child, bare group names.
    local lab="" long=1
    for ((i = 0; i < nk; i++)); do
        _gc_kv "${_GC_KIDS[$i]}" && [[ $_GC_COLON -eq 1 ]] || { long=0; break; }
        if [[ -z "$lab" ]]; then lab="$_GC_K"
        elif [[ "$_GC_K" != "$lab" ]]; then long=0; break; fi
    done
    if [[ $long -eq 1 ]]; then
        local g
        for g in "${_GC_GROUPS[@]}"; do [[ "$g" == *": "* ]] && { long=0; break; }; done
    fi
    [[ $long -eq 1 ]] && { _GC_MODE=long; return 0; }
    # WIDE: keys distinct within a group, every group shares a key with
    # another, and children average >= 1.5 per group.
    local -A seen=() cnt=()
    local prev=-1 gk="" key
    for ((i = 0; i < nk; i++)); do
        _gc_kv "${_GC_KIDS[$i]}" || return 1
        key="$_GC_K"
        [[ "$key" =~ ^[A-Za-z] ]] || return 1    # a name, not an offset/value
        if [[ ${_GC_GOF[$i]} -ne $prev ]]; then seen=(); prev=${_GC_GOF[$i]}; fi
        [[ -n "${seen[$key]:-}" ]] && return 1
        seen[$key]=1
        cnt[$key]=$(( ${cnt[$key]:-0} + 1 ))
    done
    [[ $(( nk * 2 )) -ge $(( ${#_GC_GROUPS[@]} * 3 )) ]] || return 1
    prev=-1
    local shared=0 gi
    for ((i = 0; i < nk; i++)); do
        gi=${_GC_GOF[$i]}
        if [[ $gi -ne $prev ]]; then
            [[ $prev -ge 0 && $shared -eq 0 ]] && return 1
            prev=$gi; shared=0
        fi
        _gc_kv "${_GC_KIDS[$i]}"
        [[ ${cnt[$_GC_K]} -ge 2 ]] && shared=1
    done
    [[ $shared -eq 1 ]] || return 1
    _GC_MODE=wide
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="unindented group lines over one level of indented children"
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # PREFILTER (exact): children are indented lines.
    [[ "$text" == *$'\n '* || "$text" == *$'\n\t'* ]] || return 1
    _gc_scan "$text" || return 1
    _gc_mode || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

_gc_name () {
    local s="$1"
    s="${s//[^A-Za-z0-9_%.-]/_}"
    while [[ "$s" == *__* ]]; do s="${s//__/_}"; done
    s="${s#_}"; s="${s%_}"
    _GC_NAME="$s"
}

strategy_extract () {
    local text="$1" result="" entry=0 i
    _gc_scan "$text" || return 0
    _gc_mode || return 0
    # Group column: `<same-token> <one-token>` lines name it by that token.
    local gcol="group" gtok="" g same=1
    local -a gvals=()
    for g in "${_GC_GROUPS[@]}"; do
        _fr_tok "$g"
        if [[ ${#_FR_TOK[@]} -eq 2 && ( -z "$gtok" || "${_FR_TOK[0]}" == "$gtok" ) ]]; then
            gtok="${_FR_TOK[0]}"
        else
            same=0
        fi
    done
    for g in "${_GC_GROUPS[@]}"; do
        if [[ $same -eq 1 ]]; then
            _fr_tok "$g"; gvals+=("${_FR_TOK[1]}")
        else
            g="${g%"${g##*[![:space:]]}"}"; g="${g%:}"
            gvals+=("$g")
        fi
    done
    if [[ $same -eq 1 ]]; then _gc_name "$gtok"; gcol="$_GC_NAME"; fi
    if [[ "$_GC_MODE" == long ]]; then
        for ((i = 0; i < ${#_GC_KIDS[@]}; i++)); do
            _gc_kv "${_GC_KIDS[$i]}"
            _gc_name "$_GC_K"
            entry=$((entry + 1))
            result+="entry${entry}.${gcol} ${gvals[${_GC_GOF[$i]}]}"$'\n'
            _clean_value "$_GC_V"
            result+="entry${entry}.${_GC_NAME} ${_CLEANED}"$'\n'
        done
    else
        local prev=-1
        for ((i = 0; i < ${#_GC_KIDS[@]}; i++)); do
            if [[ ${_GC_GOF[$i]} -ne $prev ]]; then
                prev=${_GC_GOF[$i]}
                entry=$((entry + 1))
                result+="entry${entry}.${gcol} ${gvals[$prev]}"$'\n'
            fi
            _gc_kv "${_GC_KIDS[$i]}"
            _gc_name "$_GC_K"
            [[ "$_GC_NAME" == "$gcol" ]] && _GC_NAME="${_GC_NAME}_2"
            _clean_value "$_GC_V"
            result+="entry${entry}.${_GC_NAME} ${_CLEANED}"$'\n'
        done
    fi
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
