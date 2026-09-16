#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: labeled-records
## Description: One record per "label: prose" line (file, and similar per-line labelled output)
## Version: 1.0
## Priority: 40
## Sample: samples/labeled-records/basic.txt

# For output where EVERY line is `<single-token-label>: <prose value>` — e.g.
# `file` output ("archive.tar.gz: gzip compressed data, …"). Each line is a
# distinct record, so this melts to one row per line with (name, value) columns.
#
# The single-token label + letter-initial value signature separates it from:
#   - key/value snapshots with numeric values (/proc/meminfo "MemTotal: 8173456 kB")
#   - status output with multi-word labels (hostnamectl "Static hostname: …")
# both of which are single-observation and handled by yaml/colons.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local n=0 match=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        n=$((n + 1))
        # single-token label (no space before the colon), then a value starting
        # with a letter (prose, not a number)
        [[ "$_l" =~ ^[[:space:]]*[^[:space:]]+:[[:space:]]+[A-Za-z] ]] && match=$((match + 1))
        [[ $n -ge 40 ]] && break
    done <<< "$text"

    # Every non-blank line must fit, and we need at least two records.
    [[ $n -ge 2 && $match -eq $n ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        local key="${_l%%:*}" val="${_l#*:}"
        # trim
        key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${key}"$'\n'
        [[ -n "$val" ]] && result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
