#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: ini-sections
## Description: Multi-section INI/config ([section] + key=value) flattened to (section, key, value) rows
## Version: 1.0
## Priority: 20
## Sample: samples/ini-sections/basic.ini

# Classic INI / config-dump output — several [section] blocks, each a run of
# `key = value` (or `key=value`) lines:
#
#     [server]                 [database]
#     host = 10.0.0.1          host = 10.0.0.5
#     port = 8080              port = 5432
#
# The plain `equals` parser flattens every pair into ONE wide record, which
# collides duplicate keys across sections (three `host` columns) and drops the
# section a value belongs to. The correct, lossless tidy is one row per pair with
# its section carried alongside: (section, key, value). We fire only when the
# section names are simple tokens AND distinct — repeated-section block formats
# (ffprobe `[STREAM]…[/STREAM]`) and spaced section names (`[Unit foo.target]`)
# are left to their better-fitting parsers. `toml` (priority 15) still wins real
# TOML (quoted values, dotted/array tables) since it is tried first.
#
# The line classifier is inlined into both detect and extract (rather than a
# shared helper) on purpose: the engine unsets `_strat_*` helper functions
# between the detection sweep and extraction, so a helper would vanish before
# strategy_extract runs.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # INI legitimately begins with '['; only a leading '{' means real JSON here
    # (a bare _is_json check treats the opening [section] as a JSON array).
    case "${text#"${text%%[![:space:]]*}"}" in '{'*) return 1 ;; esac
    local _line l inner k _seen="|" _sec=0 _kv=0 _dup=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        l="$_line"
        while [[ "$l" == " "* || "$l" == $'\t'* ]]; do l="${l#?}"; done
        while [[ "$l" == *" " || "$l" == *$'\t' ]]; do l="${l%?}"; done
        [[ -z "$l" ]] && continue
        case "$l" in '#'*|';'*) continue ;; esac
        if [[ "$l" == "["*"]" ]]; then
            inner="${l#[}"; inner="${inner%]}"
            case "$inner" in
                ""|*[!A-Za-z0-9_.:-]*) ;;
                [A-Za-z]*)
                    _sec=$((_sec + 1))
                    case "$_seen" in *"|${inner}|"*) _dup=1 ;; esac
                    _seen="${_seen}${inner}|"
                    continue ;;
            esac
        fi
        if [[ "$l" == *"="* ]]; then
            k="${l%%=*}"
            while [[ "$k" == *" " || "$k" == *$'\t' ]]; do k="${k%?}"; done
            case "$k" in
                ""|*[!A-Za-z0-9_.-]*) ;;
                *) _kv=$((_kv + 1)) ;;
            esac
        fi
    done
    [[ $_sec -ge 2 && $_dup -eq 0 && $_kv -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    _STRATEGY_CONFIDENCE_REASON="multi-section INI ([section] + key=value), distinct section names"
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 _line l inner k value section=""
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        l="$_line"
        while [[ "$l" == " "* || "$l" == $'\t'* ]]; do l="${l#?}"; done
        while [[ "$l" == *" " || "$l" == *$'\t' ]]; do l="${l%?}"; done
        [[ -z "$l" ]] && continue
        case "$l" in '#'*|';'*) continue ;; esac
        # section header?
        if [[ "$l" == "["*"]" ]]; then
            inner="${l#[}"; inner="${inner%]}"
            case "$inner" in
                ""|*[!A-Za-z0-9_.:-]*) ;;
                [A-Za-z]*) section="$inner"; continue ;;
            esac
        fi
        # key = value?
        [[ "$l" == *"="* ]] || continue
        k="${l%%=*}"
        while [[ "$k" == *" " || "$k" == *$'\t' ]]; do k="${k%?}"; done
        case "$k" in ""|*[!A-Za-z0-9_.-]*) continue ;; esac
        value="${l#*=}"
        while [[ "$value" == " "* || "$value" == $'\t'* ]]; do value="${value#?}"; done
        while [[ "$value" == *" " || "$value" == *$'\t' ]]; do value="${value%?}"; done
        entry=$((entry + 1))
        result+="entry${entry}.section ${section}"$'\n'
        result+="entry${entry}.key ${k}"$'\n'
        [[ -n "$value" ]] && result+="entry${entry}.value ${value}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
