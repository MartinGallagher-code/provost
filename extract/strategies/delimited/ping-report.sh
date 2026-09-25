#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: ping-report
## Description: ping/arping reply streams — one row per reply, summary chrome dropped
## Version: 1.0
## Priority: 35
## Sample: samples/ping-report/ping.txt

# The ping family (`ping`, `ping6`, `arping`): a banner, repeated REPLY rows
# (`64 bytes from 93.184.216.34: icmp_seq=1 ttl=56 time=11.4 ms`,
# `60 bytes from 00:14:bf:… (192.168.1.1): index=0 time=1.234 msec`), then a
# `--- … statistics ---` footer with prose summaries. The replies are the
# dataset: one row each — bytes, from, optional ip, then a column per k=v
# pair with a trailing bare unit token folded into the previous value. The
# banner/footer/summary lines are chrome and are dropped.

_pr_is_reply () {
    [[ "$1" =~ ^[0-9]+\ bytes\ from\ [^[:space:]]+ && "$1" == *": "* && "$1" == *=* ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local _l nb=0 replies=0
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        nb=$((nb + 1))
        _pr_is_reply "$_l" && replies=$((replies + 1))
        [[ $nb -ge 60 ]] && break
    done
    [[ $replies -ge 2 && $(( replies * 100 / nb )) -ge 40 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        _pr_is_reply "$_l" || continue
        entry=$((entry + 1))
        local toks=() t i
        { _fr_tok "$_l"; toks=("${_FR_TOK[@]}"); }
        result+="entry${entry}.bytes ${toks[0]}"$'\n'
        # toks[1]=bytes toks[2]=from toks[3]=<addr>[:]
        local _from="${toks[3]%:}"
        result+="entry${entry}.from ${_from}"$'\n'
        i=4
        # optional `(ip):` / `(ip)` token — regex via a variable: a literal
        # `)` inside a bracket class confuses the [[ ]] parser inline.
        local _ip_re='^\(([^)]+)\):?$'
        if [[ "${toks[4]:-}" =~ $_ip_re ]]; then
            result+="entry${entry}.ip ${BASH_REMATCH[1]}"$'\n'
            i=5
        fi
        local _lastkey=""
        for ((; i < ${#toks[@]}; i++)); do
            t="${toks[$i]}"
            if [[ "$t" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
                _lastkey="${BASH_REMATCH[1]}"
                result+="entry${entry}.${_lastkey} ${BASH_REMATCH[2]}"$'\n'
            elif [[ -n "$_lastkey" && "$t" =~ ^[A-Za-z%/]+$ ]]; then
                # bare unit token (`ms`, `msec`) folds into the last value
                result="${result%$'\n'} ${t}"$'\n'
            fi
        done
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
