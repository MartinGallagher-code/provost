#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: numastat
## Description: Extract per-node memory counters from `numastat` output
## Version: 1.0
## Priority: 26
## Sample: samples/numastat/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: a header row whose every token matches nodeN
    # (node0 node1 ...), followed by "metric val0 val1" rows. df-h.txt's header
    # is "Filesystem Size Used ..." — no node tokens — so it declines.
    local line first="" tok ok=0 seen_header=0
    while IFS= read -r line; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ $seen_header -eq 0 ]]; then
            seen_header=1
            ok=1
            local ntok=0
            for tok in $line; do
                ntok=$((ntok + 1))
                [[ "$tok" =~ ^node[0-9]+$ ]] || { ok=0; break; }
            done
            [[ $ntok -ge 1 ]] || ok=0
            [[ $ok -eq 1 ]] || return 1
        fi
    done <<< "$text"
    if [[ $ok -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line seen_header=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ $seen_header -eq 0 ]]; then
            seen_header=1     # skip the "node0 node1" header row
            continue
        fi
        # metric  node0val  node1val ...
        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        [[ ${#f[@]} -ge 2 ]] || continue
        local metric="${f[0]}"
        entry=$((entry + 1))
        result+="entry${entry}.metric ${metric}"$'\n'
        result+="entry${entry}.node0 ${f[1]}"$'\n'
        [[ ${#f[@]} -ge 3 ]] && result+="entry${entry}.node1 ${f[2]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
