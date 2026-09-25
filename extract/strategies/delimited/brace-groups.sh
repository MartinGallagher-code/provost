#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: brace-groups
## Description: `name { ... }` config blocks (lvmconfig, nginx upstreams) -> group/key/value or group/value rows
## Version: 1.0
## Priority: 33
## Sample: samples/brace-groups/basic.txt

# Config dumps of named brace blocks:
#
#   config {              upstream backend {
#       checks=1              least_conn;
#   }                         server 10.0.0.11:8080 weight=3;
#                         }
#
# The reviewer: the block NAME is a column, each line inside is a value
# against it. When EVERY member is a tight `key=value`, the pair splits into
# `group | key | value` (lvmconfig); otherwise `group | value` (nginx, whose
# members are directives). A trailing `;` on a member is config punctuation
# and dropped. Repeated group names are records, not collisions.
#
# Gates: >=2 blocks; the opener is `name {` (name may be several words, no
# braces/semicolons); every non-blank line is an opener, a member, or a
# lone `}`; members are indented; nothing outside blocks except blank lines.
_brg_open_re='^([A-Za-z_][A-Za-z0-9_ .-]*)[[:space:]]\{$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line blocks=0 members=0 inblock=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ $_brg_open_re ]]; then
            [[ $inblock -eq 1 ]] && return 1     # nested blocks: not this shape
            inblock=1; blocks=$((blocks + 1)); continue
        fi
        if [[ "${line//[[:space:]]/}" == "}" ]]; then
            [[ $inblock -eq 0 ]] && return 1
            inblock=0; continue
        fi
        [[ $inblock -eq 0 ]] && return 1          # content outside any block
        [[ "$line" == [' 	']* ]] || return 1      # members are indented
        members=$((members + 1))
    done
    [[ $inblock -eq 0 ]] || return 1              # unclosed block
    [[ $blocks -ge 2 && $members -ge $blocks ]] || return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"
    local line group="" body result="" entry=0

    # All-kv? Every member a tight single-token k=v (after `;`-strip).
    local allkv=1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        [[ "$line" =~ $_brg_open_re ]] && continue
        [[ "${line//[[:space:]]/}" == "}" ]] && continue
        body="${line#"${line%%[![:space:]]*}"}"; body="${body%"${body##*[![:space:]]}"}"
        body="${body%;}"
        [[ "$body" =~ ^[A-Za-z_][A-Za-z0-9_.-]*=[^=[:space:]]+$ ]] || { allkv=0; break; }
    done <<< "$text"

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ $_brg_open_re ]]; then
            group="${BASH_REMATCH[1]}"
            group="${group%"${group##*[![:space:]]}"}"
            continue
        fi
        [[ "${line//[[:space:]]/}" == "}" ]] && { group=""; continue; }
        [[ -n "$group" ]] || continue
        body="${line#"${line%%[![:space:]]*}"}"; body="${body%"${body##*[![:space:]]}"}"
        body="${body%;}"
        entry=$((entry + 1))
        result+="entry${entry}.group ${group}"$'\n'
        if [[ $allkv -eq 1 ]]; then
            result+="entry${entry}.key ${body%%=*}"$'\n'
            result+="entry${entry}.value ${body#*=}"$'\n'
        else
            result+="entry${entry}.value ${body}"$'\n'
        fi
    done
    line=""
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
