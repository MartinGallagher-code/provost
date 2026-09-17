#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: middot-split
## Description: lines split on a ` · ` middle-dot separator (navi cheatsheets) -> key/value rows — hint-routed
## Version: 1.0
## Priority: 99
## Sample: samples/middot-split/basic.txt

# `navi` lists cheatsheet entries as `tag · description`, using a middle dot
# (U+00B7) as the column separator:
#
#   git · undo last commit
#   docker · remove all stopped containers
#
# It kept each line as one opaque cell. Splitting on the ` · ` gives the two
# columns:
#
#   key      value
#   git      undo last commit
#   docker   remove all stopped containers
#
# HINT-ONLY: routes on the ` · ` separator via hints.tsv.

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Every record must carry the separator; a line without it means this
        # isn't a clean two-column list — bail to auto-detection.
        [[ "$line" != *" · "* ]] && return 0
        local key="${line%% · *}" val="${line#* · }"
        key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.key ${key}"$'\n'
        [[ -n "$val" ]] && result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
