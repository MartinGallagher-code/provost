#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: clickhouse-processlist
## Description: Extract rows from a ClickHouse PrettyCompact Unicode box table
## Version: 1.0
## Priority: 9
## Sample: samples/clickhouse-processlist/basic.txt

# ClickHouse's PrettyCompact format draws a Unicode box table. Column names live
# in the top border line and each data row is delimited by vertical bars:
#   ┌─user─┬─query_id─┬─address─┬─elapsed─┬─read_rows─┬─memory_usage─┐
#   │ default │ 9f3c... │ 10.0.0.5:41022 │ 0.145 │ 120340 │ 33554432 │
#   └─────────┴──────────┴────────────────┴─────────┴───────────┴──────────┘
# Generic table parsers mangle the box-drawing characters, so we handle it here.

# Box-drawing characters (UTF-8).
_CH_BAR=$'│'    # │  cell separator
_CH_TL=$'┌'     # ┌  top-left
_CH_TR=$'┐'     # ┐  top-right
_CH_TD=$'┬'     # ┬  top tee (column split in header)
_CH_DASH=$'─'   # ─  horizontal fill
_CH_BL=$'└'     # └  bottom-left
_CH_ML=$'├'     # ├  mid-left

_ch_trim () {
    # Trim leading/trailing whitespace; echo result.
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_ch_sanitise () {
    # Collapse whitespace runs to single underscores. Used for column HEADERS,
    # where the whole label becomes a field NAME.
    local s
    s="$(_ch_trim "$1")"
    s="${s//$'\t'/ }"
    while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
    printf '%s' "${s// /_}"
}

_ch_value () {
    # Sanitise a data cell VALUE: trim edges and map tabs to underscores, but
    # PRESERVE spaces (the engine keeps everything after the first space intact).
    local s
    s="$(_ch_trim "$1")"
    printf '%s' "${s//$'\t'/_}"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    # Distinctive signature: a top-border line and a bar-delimited data line.
    # (some line starts with X iff the text starts with X or holds "\nX" —
    # whole-text tests instead of a walk over every line)
    local has_border=0 has_bar=0
    [[ "$text" == "$_CH_TL"* || "$text" == *$'\n'"$_CH_TL"* ]] && has_border=1
    [[ $has_border -eq 1 ]] || return 1
    [[ "$text" == "$_CH_BAR"* || "$text" == *$'\n'"$_CH_BAR"* ]] && has_bar=1
    [[ $has_bar -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a cols=()
    local ncols=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue

        # Header: top border line carries the column names.
        if [[ "$line" == "$_CH_TL"* ]]; then
            local hdr="$line"
            hdr="${hdr//$_CH_TL/}"
            hdr="${hdr//$_CH_TR/}"
            # Split on the top tee to isolate each column label.
            local IFS_save="$IFS"
            local rest="$hdr" seg
            cols=()
            while [[ "$rest" == *"$_CH_TD"* ]]; do
                seg="${rest%%$_CH_TD*}"
                rest="${rest#*$_CH_TD}"
                seg="${seg//$_CH_DASH/}"
                cols+=("$(_ch_sanitise "$seg")")
            done
            rest="${rest//$_CH_DASH/}"
            cols+=("$(_ch_sanitise "$rest")")
            IFS="$IFS_save"
            ncols=${#cols[@]}
            continue
        fi

        # Skip other border lines (mid/bottom).
        [[ "$line" == "$_CH_ML"* ]] && continue
        [[ "$line" == "$_CH_BL"* ]] && continue

        # Data row: bar-delimited cells.
        if [[ "$line" == "$_CH_BAR"* ]]; then
            local row="${line//$_CH_BAR/|}"
            row="${row#|}"
            row="${row%|}"
            entry=$((entry + 1))
            local idx=0 cell field rest2="$row"
            while :; do
                cell="${rest2%%|*}"
                field="${cols[$idx]:-col$((idx + 1))}"
                [[ -z "$field" ]] && field="col$((idx + 1))"
                result+="entry${entry}.${field} $(_ch_value "$cell")"$'\n'
                idx=$((idx + 1))
                [[ "$rest2" == *"|"* ]] || break
                rest2="${rest2#*|}"
            done
        fi
    done

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
