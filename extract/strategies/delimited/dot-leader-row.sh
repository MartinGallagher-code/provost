#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: dot-leader-row
## Description: rows padded with a run of filler dots, result in trailing [brackets] (pytest, dbt) -> left fields + result columns — hint-routed
## Version: 1.0
## Priority: 47
## Sample: samples/dot-leader-row/basic.txt

# Progress-style listings pad each row with a run of dots and put the result
# at the right edge, usually bracketed:
#
#   tests/test_parser.py ........................        [ 40%]
#   tests/test_engine.py ....................F...        [ 88%]
#   14:22:33  PASS not_null_orders_order_id ....... [PASS in 1.42s]
#
# The reviewer: "filler = a `.` and square brackets should be removed",
# "remove the .... and put the data into different columns". A qualifying row
# (it carries a dot-run of 3+) is peeled from the right: a trailing `[...]`
# gives the bracket-stripped `result`; the left side's whitespace fields become
# positional columns A, B, C, ... with dot-filler stripped from each token
# (pytest's `....F...` tick string reduces to its non-dot markers, `F`; a
# token that is only dots drops entirely):
#
#   A                     B     C                          result
#   tests/test_parser.py                                   40%
#   14:22:33              PASS  not_null_orders_order_id   PASS in 1.42s
#
# Lines with no dot-run (banners, platform/summary chrome) are skipped.
#
# HINT-ONLY: dot-leader layouts vary too much to auto-fire safely.

_dlr_dots='\.\.\.'
_dlr_br='^(.*)\[([^][]*)\][[:space:]]*$'

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        # Qualify: the line must carry a dot-run of 3+ somewhere.
        [[ "$line" =~ $_dlr_dots ]] || continue
        local left="$line" right=""
        if [[ "$line" =~ $_dlr_br ]]; then
            left="${BASH_REMATCH[1]}"; right="${BASH_REMATCH[2]}"
        fi
        right="${right#"${right%%[![:space:]]*}"}"
        right="${right%"${right##*[![:space:]]}"}"
        entry=$((entry + 1))
        local letters=(A B C D E F G H) idx=0 tok
        for tok in $left; do
            # A token carrying a 3+ dot-run is filler: remove its dots and
            # keep any markers (pytest's `....F...` -> `F`); drop it if
            # nothing remains. A token with only single dots (a filename,
            # a version) is real content and stays whole.
            if [[ "$tok" =~ $_dlr_dots ]]; then tok="${tok//./}"; fi
            [[ -z "$tok" ]] && continue
            [[ $idx -ge ${#letters[@]} ]] && break
            result+="entry${entry}.${letters[idx]} ${tok}"$'\n'
            idx=$((idx + 1))
        done
        [[ -n "$right" ]] && result+="entry${entry}.result ${right}"$'\n'
    done
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
