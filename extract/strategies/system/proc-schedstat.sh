#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: proc-schedstat
## Description: Extract per-CPU scheduler statistics from /proc/schedstat
## Version: 1.0
## Priority: 20
## Sample: samples/proc-schedstat/basic.txt

# /proc/schedstat starts with "version N" and "timestamp N", then per-CPU lines
#   cpu0 0 0 0 0 0 0 <run> <wait> <slices>
# each followed by "domainN ..." rows. We keep one record per cpuN line (its 9
# counters) and skip version/timestamp/domain lines.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *"timestamp "* ]] || return 1
    [[ "$text" == *"domain0 "* ]] || return 1
    [[ "$text" == *"cpu0 "* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == cpu[0-9]* ]] || continue

        local -a f=()
        read -ra f <<< "$line"
        # f: cpuN c1 c2 ... c9
        [[ ${#f[@]} -lt 10 ]] && continue

        n=$((n + 1))
        result+="entry${n}.cpu ${f[0]}"$'\n'
        local i
        for ((i = 1; i <= 9; i++)); do
            result+="entry${n}.col${i} ${f[$i]}"$'\n'
        done
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
