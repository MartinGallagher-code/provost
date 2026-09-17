#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: pipe-cells
## Description: Monitor rows like `PRC | sys 1.42s | user 3.18s |` — a row label plus pipe-separated key/value cells (atop)
## Version: 1.0
## Priority: 31
## Sample: samples/pipe-cells/basic.txt

# atop and similar full-screen monitors print each resource group as a row:
#
#   PRC | sys    1.42s | user   3.18s | #proc    284 | #zombie    0 |
#   CPU | sys      14% | user     31% | irq       2% | idle    248% |
#
# a short row LABEL, then `|`-separated cells that are each a `key value` pair.
# The keys differ line to line, so a wide-per-line table is sparse mush and
# aligned-columns keeps the `|` glyphs as columns. The tidy shape is long:
# one row per cell — group / key / value — with the pipes gone. Distinct enough
# not to poach real pipe tables: the label sits OUTSIDE the pipes, the row ends
# in a pipe, and every cell is a two-token key/value (a data table's cells are
# lone values).

# A pipe-cells row: sets nothing, returns 0/1. `LABEL | k v | k v | … |`
_pc_row () {
    local line="$1"
    # Leading label: uppercase-led short token, then ` | `.
    [[ "$line" =~ ^[A-Z][A-Za-z0-9#_]{0,5}[[:space:]]*\|[[:space:]] ]] || return 1
    # Must carry >=2 pipes and end (after trailing spaces) with a pipe.
    local t="${line%"${line##*[![:space:]]}"}"   # rstrip
    [[ "$t" == *"|" ]] || return 1
    local bars="${line//[^|]/}"
    [[ ${#bars} -ge 2 ]] || return 1
    # Every non-empty cell after the label must be a key/value (>=2 tokens).
    local rest="${line#*|}"
    local -a cells=(); IFS='|' read -ra cells <<< "$rest"
    # Count key/value cells (>=2 tokens). Empty cells (SWP's gap) and a single
    # lone-value cell (DSK's `sda` device name) are tolerated and skipped; a
    # real 2-/3-column pipe table has only lone-value cells and so scores 0.
    local seen=0 c
    for c in "${cells[@]}"; do
        local -a tk=(); read -ra tk <<< "$c"
        [[ ${#tk[@]} -ge 2 ]] && seen=$((seen + 1))
    done
    [[ $seen -ge 2 ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line hits=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _pc_row "$line" && hits=$((hits + 1))
        [[ $hits -ge 3 ]] && { _STRATEGY_CONFIDENCE=80; return 0; }
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        _pc_row "$line" || continue
        local group="${line%%|*}"
        group="${group%"${group##*[![:space:]]}"}"      # rstrip
        group="${group#"${group%%[![:space:]]*}"}"      # lstrip
        local rest="${line#*|}"
        local IFS='|'; local -a cells=(); read -ra cells <<< "$rest"; unset IFS
        local c
        for c in "${cells[@]}"; do
            local -a tk=(); read -ra tk <<< "$c"
            [[ ${#tk[@]} -lt 2 ]] && continue
            local key="${tk[0]}" val="${tk[*]:1}"
            entry=$((entry + 1))
            result+="entry${entry}.group ${group}"$'\n'
            result+="entry${entry}.key ${key}"$'\n'
            result+="entry${entry}.value ${val}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
