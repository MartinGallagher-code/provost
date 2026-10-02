#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: user-groups
## Description: `groups` output — "user : group1 group2 …" → one row per membership
## Version: 1.0
## Priority: 30
## Sample: samples/user-groups/basic.txt

# `groups` (and `groups <user>`) prints a single line: a user, " : ", then a
# space-separated list of the user's groups. Tidied to one row per membership
# with (user, group) columns. The distinctive " : " (space-colon-space) after a
# single token, on a lone line, keys the detection.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local nonblank=0 first="" _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        nonblank=$((nonblank + 1))
        [[ -z "$first" ]] && first="$_l"
    done
    [[ $nonblank -eq 1 ]] || return 1
    [[ "$first" =~ ^[a-zA-Z0-9_.-]+[[:space:]]+:[[:space:]]+[a-zA-Z] ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local first="" _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && { continue; }
        first="$_l"; break
    done

    local toks; toks=(); { _fr_tok "$first"; toks=("${_FR_TOK[@]}"); }
    local user="${toks[0]}"
    local result="" entry=0 i seen_sep=0
    for ((i = 1; i < ${#toks[@]}; i++)); do
        if [[ "${toks[$i]}" == ":" && $seen_sep -eq 0 ]]; then seen_sep=1; continue; fi
        [[ $seen_sep -eq 0 ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.user ${user}"$'\n'
        result+="entry${entry}.group ${toks[$i]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
