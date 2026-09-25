#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: arrow-info-records
## Description: yarn-why `=> Found …` + `info …` + indented bullets -> label/value rows, label carried onto bullets
## Version: 1.0
## Priority: 39
## Sample: samples/arrow-info-records/basic.txt

# yarn why's answer shape:
#
#   => Found "lodash@4.17.21"
#   info Reasons this module exists
#      - "webpack#loader-utils" depends on it
#      - Hoisted from "webpack#loader-utils#lodash"
#
# text-lines kept it as four one-cell rows. The reviewer: "Column A: Found,
# info, info, info. Column B: the rest." The `=>` arrow is chrome; the first
# word of each unindented line is the label; an indented `- ` bullet inherits
# the label above it, bullet marker dropped:
#
#   label  value
#   Found  "lodash@4.17.21"
#   info   Reasons this module exists
#   info   "webpack#loader-utils" depends on it
#   info   Hoisted from "webpack#loader-utils#lodash"
#
# Detection: the FIRST non-blank line is `=> Word …`, every other line is
# either `word …` (unindented) or an indented `- ` bullet, and >=1 bullet
# exists. The arrow-lead first line is the signature.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line first=1 bullets=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ $first -eq 1 ]]; then
            [[ "$line" =~ ^=\>[[:space:]]+[A-Za-z]+[[:space:]] ]] || return 1
            first=0; continue
        fi
        if [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
            bullets=$((bullets + 1)); continue
        fi
        [[ "$line" =~ ^[A-Za-z]+[[:space:]] ]] || return 1
    done
    [[ $first -eq 0 && $bullets -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 label=""
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ ^=\>[[:space:]]+([A-Za-z]+)[[:space:]]+(.+)$ ]]; then
            label="${BASH_REMATCH[1]}"
            entry=$((entry + 1))
            result+="entry${entry}.label ${label}"$'\n'
            result+="entry${entry}.value ${BASH_REMATCH[2]}"$'\n'
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.+)$ ]]; then
            [[ -n "$label" ]] || continue
            entry=$((entry + 1))
            result+="entry${entry}.label ${label}"$'\n'
            result+="entry${entry}.value ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ ^([A-Za-z]+)[[:space:]]+(.+)$ ]]; then
            label="${BASH_REMATCH[1]}"
            entry=$((entry + 1))
            result+="entry${entry}.label ${label}"$'\n'
            result+="entry${entry}.value ${BASH_REMATCH[2]}"$'\n'
        fi
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
