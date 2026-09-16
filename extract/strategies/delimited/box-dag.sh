#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: box-dag
## Description: ASCII-boxed pipeline DAG (dvc dag) -> one row per stage, in graph order
## Version: 1.0
## Priority: 30
## Sample: samples/box-dag/basic.txt

# `dvc dag` draws each pipeline stage in its own one-line ASCII box, chained by
# `*` edge lines:
#
#   +----------------+
#   | data/raw.csv   |
#   +----------------+
#           *
#   +----------------+
#   | preprocess     |
#   +----------------+
#
# psql-table sees the `+---+` borders as its own table chrome and promotes the
# FIRST stage to a column name. The data here is the stage sequence: one row
# per box, in the order drawn — `stage` column, graph order = row order. Edge
# glyph lines (`*`, `**`, `/`, `\`, `|` and whitespace) carry no fields worth
# columns for a straight chain and are dropped; the drawing IS the order.
#
# Detection: >=2 boxes, and EVERY non-blank line is a border, a box content
# line, or an edge-glyph line — one stray prose or data line rejects, so real
# psql/box tables (which have multi-column content rows) are never touched.

_bd_border_re='^[[:space:]]*\+[-+]+\+[[:space:]]*$'
_bd_content_re='^[[:space:]]*\|.*\|[[:space:]]*$'
_bd_edge_re='^[[:space:]]*[*/\|\\ ]+[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line borders=0 contents=0 mcol=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_bd_border_re ]]; then borders=$((borders + 1)); continue; fi
        if [[ "$line" =~ $_bd_content_re ]]; then
            contents=$((contents + 1))
            # An interior `|` means a MULTI-COLUMN row — that is a real box
            # table (psql), not a DAG node.
            local inner="${line#*|}"; inner="${inner%|*}"
            [[ "$inner" == *'|'* ]] && mcol=1
            continue
        fi
        [[ "$line" =~ $_bd_edge_re ]] && continue
        return 1
    done <<< "$text"
    # A DAG: >=2 one-cell boxes (each its own border pair), single-column only.
    [[ $mcol -eq 0 && $contents -ge 2 && $borders -ge 4 ]] || return 1
    _STRATEGY_CONFIDENCE=82
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ $_bd_content_re ]] || continue
        local inner="${line#*|}"; inner="${inner%|*}"
        inner="${inner#"${inner%%[![:space:]]*}"}"
        inner="${inner%"${inner##*[![:space:]]}"}"
        [[ -n "$inner" ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.stage ${inner}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
