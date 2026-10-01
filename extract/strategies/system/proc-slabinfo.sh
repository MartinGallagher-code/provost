#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: proc-slabinfo
## Description: Extract per-cache stats from /proc/slabinfo output
## Version: 1.0
## Priority: 26
## Sample: samples/proc-slabinfo/basic.txt

# /proc/slabinfo starts with a `slabinfo - version: 2.1` line and a `# name ...`
# header, then one row per kmem cache:
#   kmalloc-8192  128  128  8192  4  8 : tunables 0 0 0 : slabdata 32 32 0
# We emit one record per cache, keeping the first six columns (name,
# active_objs, num_objs, objsize, objperslab, pagesperslab) and skipping the
# version and `#` header lines.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    [[ "$text" == *"slabinfo - version:"* ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "slabinfo - version:"* ]] && continue
        [[ "$line" == "#"* ]] && continue

        local -a f=()
        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        [[ ${#f[@]} -lt 6 ]] && continue

        n=$((n + 1))
        result+="entry${n}.name ${f[0]}"$'\n'
        result+="entry${n}.active_objs ${f[1]}"$'\n'
        result+="entry${n}.num_objs ${f[2]}"$'\n'
        result+="entry${n}.objsize ${f[3]}"$'\n'
        result+="entry${n}.objperslab ${f[4]}"$'\n'
        result+="entry${n}.pagesperslab ${f[5]}"$'\n'
    done

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
