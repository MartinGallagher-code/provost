#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: bcc-funccount
## Description: bcc funccount FUNC/COUNT table → one tidy row per function
## Version: 1.0
## Priority: 22
## Sample: samples/bcc-funccount/basic.txt

# bcc's `funccount` prints a "Tracing N functions ..." line, a "^C" interrupt
# marker, a "FUNC   COUNT" header, one row per traced function, then a
# "Detaching..." footer. A function row has exactly two fields whose second
# field (count) is an integer — that distinguishes it from every non-data line.

_bcc_funccount_is_row () {
    # $1 = field count, $2 = the count token, $3 = the FUNC token
    [[ "$1" -eq 2 && "$2" =~ ^[0-9]+$ && "$3" != "FUNC" ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Tracing"* && "$text" == *"FUNC"* && "$text" == *"COUNT"* ]] || return 1
    _STRATEGY_CONFIDENCE=88
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local toks
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        toks=(); { _fr_tok "$line"; toks=("${_FR_TOK[@]}"); }
        _bcc_funccount_is_row "${#toks[@]}" "${toks[1]:-}" "${toks[0]:-}" || continue
        entry=$((entry + 1))
        result+="entry${entry}.func ${toks[0]}"$'\n'
        result+="entry${entry}.count ${toks[1]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
