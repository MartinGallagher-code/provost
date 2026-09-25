#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: jj-log
## Description: Extract changes from a Jujutsu `jj log` graph
## Version: 1.0
## Priority: 22
## Sample: samples/jj-log/basic.txt

# `jj log` draws a graph; node lines carry the change id, author, timestamp and
# commit id, e.g.
#   @  qpvuntsm alice@example.com 2026-07-06 10:15:42 a1b2c3d4
# Description continuation lines and the synthetic root() node (no author email)
# are skipped, so only real changes are counted.

_jjlog_is_node () {
    [[ "$1" =~ [^[:space:]]+@[^[:space:]]+\.[^[:space:]]+[[:space:]]+20[0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has=0
    # PREFILTER (exact): a node line holds `@` and a `20YY-MM-DD<space>` date.
    [[ "$text" == *@* && "$text" == *20[0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]* ]] || return 1
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _jjlog_is_node "$line" && has=1
    done
    if [[ $has -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a a
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _jjlog_is_node "$line" || continue
        { _fr_tok "$line"; a=("${_FR_TOK[@]}"); }
        # a[0]=graph glyph, a[1]=change id, a[2]=author, a[3]=date, last=commit id
        local change="${a[1]}" author="${a[2]}" datev="${a[3]}"
        local commit="${a[$((${#a[@]}-1))]}"
        entry=$((entry + 1))
        result+="entry${entry}.change ${change}"$'\n'
        result+="entry${entry}.author ${author}"$'\n'
        result+="entry${entry}.date ${datev}"$'\n'
        result+="entry${entry}.commit ${commit}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
