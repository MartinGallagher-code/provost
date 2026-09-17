#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: haproxy-vv
## Description: Extract build/settings key-values from `haproxy -vv`
## Version: 1.0
## Priority: 20
## Sample: samples/haproxy-vv/basic.txt

# `haproxy -vv` prints a "HAProxy version ..." banner followed by "key = value"
# lines (build options + default settings). This is a key/value snapshot: emit a
# single wide record `entry1.<key> value` for every "key = value" line, then
# total_entries 1.

_hv_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }
_hv_key () {
    local k="$1"
    k="${k#"${k%%[![:space:]]*}"}"   # ltrim
    k="${k%"${k##*[![:space:]]}"}"   # rtrim
    k="${k//[[:space:]]/_}"
    k="${k//./_}"
    printf '%s' "$k"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"HAProxy version"* ]] || return 1
    [[ "$text" == *"="* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" n=0 line key val
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == *"="* ]] || continue
        key="$(_hv_key "${line%%=*}")"
        [[ -n "$key" ]] || continue
        val="${line#*=}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        n=$((n + 1))
        result+="entry1.${key} $(_hv_san "$val")"$'\n'
    done <<< "$text"
    [[ $n -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
