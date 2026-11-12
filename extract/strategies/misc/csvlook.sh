#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: csvlook
## Description: Extract rows from a csvlook / Markdown pipe table (skips the |---| separator row)
## Version: 1.0
## Priority: 22
## Commands: csvlook *
## Sample: samples/csvlook/basic.txt

# `csvlook` renders a Markdown-style table: a header row of pipe-delimited column
# names, a "| --- | --- |" separator row, then one data row per record. The
# header names the fields; the separator row is skipped; each data row becomes a
# record.

# A markdown separator row is ENTIRELY `|`, `-`, `:` and spaces (every cell is
# `---`) — and contains at least one dash. A data row with a lone `-` cell (e.g.
# an `aws --output table` box row "| ... | - | ... |") is NOT a separator.
_csvlook_is_sep () {
    local l="$1"
    [[ "$l" == *"-"* ]] || return 1
    [[ "$l" =~ ^[[:space:]]*\|[-:|[:space:]]*\|[[:space:]]*$ ]] || return 1
    return 0
}

_csvlook_cells () {
    # Splits one pipe-delimited row into the global array _CELLS, trimmed.
    local line="$1"
    while [[ "$line" == " "* ]]; do line="${line# }"; done
    [[ "$line" == "|"* ]] && line="${line#|}"
    while [[ "$line" == *" " ]]; do line="${line% }"; done
    [[ "$line" == *"|" ]] && line="${line%|}"
    local old_ifs="$IFS"; IFS='|'
    { _fr_tok "$line"; _CELLS=("${_FR_TOK[@]}"); }
    IFS="$old_ifs"
    local i c
    for ((i=0; i<${#_CELLS[@]}; i++)); do
        c="${_CELLS[$i]}"
        while [[ "$c" == " "* ]]; do c="${c# }"; done
        while [[ "$c" == *" " ]]; do c="${c% }"; done
        _CELLS[$i]="$c"
    done
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Must contain pipe rows and a dashed separator row.
    [[ "$text" == *"|"* ]] || return 1
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *"|"* ]] || continue
        if _csvlook_is_sep "$line"; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a _CELLS headers
    local have_header=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *"|"* ]] || continue
        # Separator row: cells are all dashes.
        if _csvlook_is_sep "$line"; then continue; fi
        _csvlook_cells "$line"
        if [[ $have_header -eq 0 ]]; then
            headers=("${_CELLS[@]}")
            have_header=1
            continue
        fi
        entry=$((entry + 1))
        local j name value
        for ((j=0; j<${#headers[@]}; j++)); do
            name="${headers[$j]}"
            value="${_CELLS[$j]:-}"
            name="${name// /_}"; name="${name//./_}"
            [[ -z "$name" ]] && continue
            result+="entry${entry}.${name} ${value}"$'\n'
        done
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
