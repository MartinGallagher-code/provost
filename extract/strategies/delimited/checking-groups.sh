#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: checking-groups
## Description: `Checking FILE` over indented `LEVEL: message` results (promtool check) -> file/level/message rows
## Version: 1.0
## Priority: 36
## Sample: samples/checking-groups/basic.txt

# The lint-runner report shape (promtool check config/rules, some validators):
#
#   Checking prometheus.yml
#     SUCCESS: 4 rule files found
#   Checking rules/node.yml
#     SUCCESS: 12 rules found
#
# The checked FILE is the record key and each indented `LEVEL: message` is a
# result against it — the reviewer's "not even close / you lost information"
# was the file column vanishing entirely. Emits `file | level | message`.
#
# Gates: >=2 `Checking X` headers (X a single token); every other non-blank
# line is an indented `UPPERCASE: message`; at least one result per header.
_cg_head_re='^Checking[[:space:]]+([^[:space:]]+)$'
_cg_res_re='^[[:space:]]+([A-Z]+):[[:space:]]+(.+)$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line heads=0 results=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_cg_head_re ]]; then heads=$((heads + 1))
        elif [[ "$line" =~ $_cg_res_re ]]; then
            [[ $heads -eq 0 ]] && return 1
            results=$((results + 1))
        else return 1; fi
    done <<< "$text"
    [[ $heads -ge 2 && $results -ge $heads ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local line file="" result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_cg_head_re ]]; then
            file="${BASH_REMATCH[1]}"
            continue
        fi
        [[ "$line" =~ $_cg_res_re ]] || continue
        [[ -n "$file" ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.file ${file}"$'\n'
        result+="entry${entry}.level ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.message ${BASH_REMATCH[2]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
