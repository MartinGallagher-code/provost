#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: count-percent-label
## Description: `N (P%) description` alignment/mapping summaries (bowtie2, HISAT2, STAR) -> count/percent/label rows
## Version: 1.0
## Priority: 42
## Sample: samples/count-percent-label/basic.txt

# Read-alignment tools report a nested tally where every line is a count, an
# optional share of its parent, and a description:
#
#   1000000 reads; of these:
#     1000000 (100.00%) were paired; of these:
#       45231 (4.52%) aligned concordantly 0 times
#       889012 (88.90%) aligned concordantly exactly 1 time
#   98.14% overall alignment rate
#
# A flat line list keeps all three facts welded into one cell, so neither the
# counts nor the percentages can be sorted or summed. The tidy shape splits them:
# `count`, `percent`, `label` — the reviewer's "separate the numbers, percentages
# and text into three separate columns".
#
# Indentation encodes nesting, but it is presentation, not data: the label text
# already says what each row counts, so rows are emitted flat in file order.
#
# Three line forms are accepted, and EVERY non-blank line must be one of them:
#   `N (P%) text`   -> count, percent, label
#   `N text`        -> count, "",      label
#   `P% text`       -> "",    percent, label
# The parenthesised form is the signature: at least two lines must carry it, so
# ordinary counted lists (`uniq -c`, `wc -l` tables) are left to line-records.

_cpl_re_np='^[[:space:]]*([0-9][0-9,]*)[[:space:]]+\(([0-9]+\.?[0-9]*%)\)[[:space:]]+(.+)$'
_cpl_re_n='^[[:space:]]*([0-9][0-9,]*)[[:space:]]+([^0-9(].*)$'
_cpl_re_p='^[[:space:]]*([0-9]+\.?[0-9]*%)[[:space:]]+(.+)$'

# Classify "$1" -> _CPL_COUNT, _CPL_PCT, _CPL_LABEL, _CPL_PAREN (1 if `N (P%)`).
# Returns 1 when the line is none of the three forms.
_cpl_split () {
    local l="$1"
    _CPL_COUNT=""; _CPL_PCT=""; _CPL_LABEL=""; _CPL_PAREN=0
    if [[ "$l" =~ $_cpl_re_np ]]; then
        _CPL_COUNT="${BASH_REMATCH[1]}"
        _CPL_PCT="${BASH_REMATCH[2]}"
        _CPL_LABEL="${BASH_REMATCH[3]}"
        _CPL_PAREN=1
    elif [[ "$l" =~ $_cpl_re_p ]]; then
        _CPL_PCT="${BASH_REMATCH[1]}"
        _CPL_LABEL="${BASH_REMATCH[2]}"
    elif [[ "$l" =~ $_cpl_re_n ]]; then
        _CPL_COUNT="${BASH_REMATCH[1]}"
        _CPL_LABEL="${BASH_REMATCH[2]}"
    else
        return 1
    fi
    _CPL_LABEL="${_CPL_LABEL%"${_CPL_LABEL##*[![:space:]]}"}"
    [[ -n "$_CPL_LABEL" ]] || return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1

    local line nb=0 paren=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        _cpl_split "$line" || return 1
        nb=$((nb + 1))
        [[ $_CPL_PAREN -eq 1 ]] && paren=$((paren + 1))
    done

    # >=2 `N (P%)` lines is the discriminator; a plain counted list has none.
    [[ $nb -ge 3 && $paren -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        _cpl_split "$line" || continue
        entry=$((entry + 1))
        result+="entry${entry}.count ${_CPL_COUNT:--}"$'\n'
        result+="entry${entry}.percent ${_CPL_PCT:--}"$'\n'
        result+="entry${entry}.label ${_CPL_LABEL}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
