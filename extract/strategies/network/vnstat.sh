#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: vnstat
## Description: Extract monthly traffic totals from `vnstat` output
## Version: 1.0
## Priority: 26
## Sample: samples/vnstat/basic.txt

# `vnstat` (monthly view) prints a title, a `month rx | tx | total | avg. rate`
# header, a `----` rule, one row per month, another rule, and an `estimated`
# footer:
#    2026-05      42.18 GiB |    8.91 GiB |   51.09 GiB |  158.72 kbit/s
# We emit one record per real month row, skipping title / header / rule /
# estimated. Values (number + unit) have spaces collapsed to underscores.

# Collapse a whitespace-separated segment into a single underscore token.
_vnstat_val () {
    local -a t=()
    { _fr_tok "$1"; t=("${_FR_TOK[@]}"); }
    local out="" x
    for x in "${t[@]}"; do out="${out:+${out}_}${x}"; done
    printf '%s' "${out:-NONE}"
}

# Is the first token a YYYY-MM month stamp?
_vnstat_is_month () {
    local -a t=()
    { _fr_tok "$1"; t=("${_FR_TOK[@]}"); }
    case "${t[0]}" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]) return 0 ;;
        *) return 1 ;;
    esac
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    [[ "$text" == *"avg. rate"* && "$text" == *"estimated"* ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        _vnstat_is_month "$line" || continue

        local -a segs=()
        { IFS='|' _fr_tok "$line"; segs=("${_FR_TOK[@]}"); }
        [[ ${#segs[@]} -lt 4 ]] && continue

        local -a m=()
        { _fr_tok "${segs[0]}"; m=("${_FR_TOK[@]}"); }
        local month="${m[0]}"
        # rx is the rest of segment 0 after the month stamp.
        local rx=""; local i
        for ((i=1; i<${#m[@]}; i++)); do rx="${rx:+${rx}_}${m[$i]}"; done

        n=$((n + 1))
        result+="entry${n}.month ${month}"$'\n'
        result+="entry${n}.rx ${rx:-NONE}"$'\n'
        result+="entry${n}.tx $(_vnstat_val "${segs[1]}")"$'\n'
        result+="entry${n}.total $(_vnstat_val "${segs[2]}")"$'\n'
        result+="entry${n}.rate $(_vnstat_val "${segs[3]}")"$'\n'
    done

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
