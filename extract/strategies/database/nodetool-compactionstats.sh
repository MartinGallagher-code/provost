#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: nodetool-compactionstats
## Description: Extract active compaction rows from `nodetool compactionstats`
## Version: 1.0
## Priority: 20
## Sample: samples/nodetool-compactionstats/basic.txt

# `nodetool compactionstats` prints "pending tasks: N", then an aligned table
# headed `id  compaction type  keyspace  table  completed  total  unit
# progress`. Each data row has 8 whitespace tokens and ends with a "NN.NN%"
# progress cell. Emit ONE record per compaction row; skip the pending line and
# the header.

_nc_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"pending tasks:"* ]] || return 1
    [[ "$text" == *"compaction type"* ]] || return 1
    [[ "$text" == *"progress"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line
    local -a t
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -eq 8 ]] || continue
        [[ "${t[7]}" =~ ^[0-9.]+%$ ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.id ${t[0]}"$'\n'
        result+="entry${entry}.compaction_type ${t[1]}"$'\n'
        result+="entry${entry}.keyspace ${t[2]}"$'\n'
        result+="entry${entry}.table ${t[3]}"$'\n'
        result+="entry${entry}.completed ${t[4]}"$'\n'
        result+="entry${entry}.total ${t[5]}"$'\n'
        result+="entry${entry}.unit ${t[6]}"$'\n'
        result+="entry${entry}.progress ${t[7]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
