#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: two-space-kv
## Description: aligned two-column rows split at the FIRST 2+ space run — key may hold single spaces (testssl summary) -> key/value rows — hint-routed
## Version: 1.0
## Priority: 58
## Sample: samples/two-space-kv/basic.txt

# Some summaries align a multi-word label against a value with only spacing,
# no delimiter:
#
#    Protocols     TLS 1.2 offered, TLS 1.3 offered
#    Cipher order  OK
#    Vulnerabilities  Heartbleed not vulnerable, POODLE not vulnerable
#
# The reviewer: "Two columns." The label can hold single spaces (`Cipher
# order`), so the split point is the FIRST run of 2+ spaces; the value keeps
# everything after it (including its own single and double spaces):
#
#   key             value
#   Protocols       TLS 1.2 offered, TLS 1.3 offered
#   Cipher order    OK
#
# A line with no 2+ space run has no boundary — bail so the hint falls
# through to auto-detection.
#
# HINT-ONLY: a two-space split is far too broad to auto-fire.

_tsk_re='^(.*[^ ])  +(.*)$'

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ "$s" =~ $_tsk_re ]] || return 0
        # Greedy left would eat into the value: cut at the FIRST 2+ space run
        # instead by trimming the left side of the greedy match down.
        local key="${s%%  *}" val="${s#"${s%%  *}"}"
        val="${val#"${val%%[![:space:]]*}"}"
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
