#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: proc-pagetypeinfo
## Description: Extract per-zone/migrate-type free-page counts from /proc/pagetypeinfo
## Version: 1.0
## Priority: 20
## Sample: samples/proc-pagetypeinfo/basic.txt

# /proc/pagetypeinfo has a "Free pages count per migrate type at order ..." table:
#   Node    0, zone      DMA, type    Unmovable   0  0  0  1  2 ... 0
# One row per (node, zone, migrate type) with 11 order columns. We skip the
# "Page block order:" / "Pages per block:" banners and the column header line.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *", type"* ]] || return 1
    [[ "$text" == *"Free pages count"* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == Node*", zone"*", type"* ]] || continue

        local -a f=()
        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        # f: Node <node>, zone <zone>, type <type> <order0> ... <order10>
        [[ ${#f[@]} -lt 17 ]] && continue

        local node="${f[1]%,}" zone="${f[3]%,}" type="${f[5]}"
        n=$((n + 1))
        result+="entry${n}.node ${node}"$'\n'
        result+="entry${n}.zone ${zone}"$'\n'
        result+="entry${n}.type ${type}"$'\n'
        local i
        for ((i = 0; i <= 10; i++)); do
            result+="entry${n}.order${i} ${f[$((6 + i))]}"$'\n'
        done
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
