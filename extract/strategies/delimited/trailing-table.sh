#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: trailing-table
## Description: an aligned header+rows table after a preamble block (parted -l) -> one row per table line, named columns — hint-routed
## Version: 1.0
## Priority: 48
## Sample: samples/trailing-table/basic.txt

# `parted -l` prints a `Key: value` preamble, a blank line, then a real
# aligned table:
#
#   Model: ATA Samsung SSD 870 (scsi)
#   Partition Table: gpt
#
#   Number  Start   End     Size    File system  Name  Flags
#    1      1049kB  538MB   537MB   fat32        efi   boot
#
# The reviewer: "It's just a table." The table starts at the first line whose
# 2+-space-separated fields all begin with an uppercase letter (the header —
# `File system` holds a single space and stays one field); every subsequent
# non-blank line is a data row split the same way, padded to the header
# width. The preamble is dropped.
#
# HINT-ONLY: "a table at the end" needs tool knowledge to route safely.

# Split $1 at 2+ space runs into _TT_FIELDS.
_tt_split () {
    local s="$1"
    _TT_FIELDS=()
    while [[ "$s" =~ ^(.*[^ ])\ \ +([^ ].*)$ ]]; do
        s="${BASH_REMATCH[1]}"
        _TT_FIELDS=("${BASH_REMATCH[2]}" "${_TT_FIELDS[@]}")
    done
    [[ -n "$s" ]] && _TT_FIELDS=("$s" "${_TT_FIELDS[@]}")
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 in_table=0
    local -a headers=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        if [[ $in_table -eq 0 ]]; then
            [[ -z "$s" ]] && continue
            # Header candidate: 3+ fields, every field starts uppercase,
            # no colon (a `Key: value` preamble line is not a header).
            [[ "$s" == *:* ]] && continue
            _tt_split "$s"
            [[ ${#_TT_FIELDS[@]} -ge 3 ]] || continue
            local ok=1 f
            for f in "${_TT_FIELDS[@]}"; do
                [[ "$f" =~ ^[A-Z] ]] || { ok=0; break; }
            done
            [[ $ok -eq 1 ]] || continue
            headers=("${_TT_FIELDS[@]}")
            in_table=1
            continue
        fi
        [[ -z "$s" ]] && continue
        _tt_split "$s"
        entry=$((entry + 1))
        local i col
        for ((i = 0; i < ${#headers[@]}; i++)); do
            col="${headers[i]// /_}"
            [[ $i -lt ${#_TT_FIELDS[@]} ]] || break
            result+="entry${entry}.${col} ${_TT_FIELDS[i]}"$'\n'
        done
    done <<< "$text"
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
