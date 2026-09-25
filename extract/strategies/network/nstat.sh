#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: nstat
## Description: Extract kernel network counters from `nstat` output
## Version: 1.0
## Priority: 26
## Sample: samples/nstat/basic.txt

# `nstat` prints a `#kernel` header line then one row per metric:
#   IpInReceives   284719   0.0
# columns are Metric, value, rate. We emit one record per metric, skipping the
# `#kernel` line.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    # First non-empty line must be exactly `#kernel`.
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "#kernel" ]] && return 0
        return 1
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "#kernel"* ]] && continue

        local -a f=()
        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        [[ ${#f[@]} -lt 2 ]] && continue

        n=$((n + 1))
        result+="entry${n}.metric ${f[0]}"$'\n'
        result+="entry${n}.value ${f[1]}"$'\n'
        result+="entry${n}.rate ${f[2]:-NONE}"$'\n'
    done

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
