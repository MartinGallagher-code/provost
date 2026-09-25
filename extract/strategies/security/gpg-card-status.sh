#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: gpg-card-status
## Description: `gpg --card-status` dotted "Field ....: value" snapshot
## Version: 1.0
## Priority: 26
## Sample: samples/gpg-card-status/basic.txt

# `gpg --card-status` prints a fixed set of "Label <dots>: value" lines whose
# labels are padded with dots for alignment. A generic key/value parser keeps
# the trailing dots in the field name and can trip on values with spaces; this
# lifts the whole card into one wide record.

_gpgcs_key () {
    local s="$1" out="" c i n=${#1}
    for ((i = 0; i < n; i++)); do
        c="${s:i:1}"
        case "$c" in
            [A-Za-z0-9]) out+="$c" ;;
            *) out+="_" ;;
        esac
    done
    while [[ "$out" == *__* ]]; do out="${out//__/_}"; done
    out="${out#_}"; out="${out%_}"
    printf '%s' "$out"
}

_gpgcs_val () {
    local v="$1"
    v="${v//$'\t'/ }"
    while [[ "$v" == *"  "* ]]; do v="${v//  / }"; done
    v="${v# }"; v="${v% }"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Distinctive: the dotted, colon-aligned card fields. Require several
    # dotted labels plus the OpenPGP-card-specific "Application ID" line.
    local line dotted=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ ^[A-Za-z].*\.\.+[[:space:]]*: ]] && dotted=$((dotted + 1))
    done

    [[ $dotted -ge 4 ]] || return 1
    [[ "$text" == *"Application ID"* ]] || return 1

    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line key val

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *:* ]] || continue
        key="${line%%:*}"
        val="${line#*:}"
        # Drop the alignment dots from the label.
        key="${key//./ }"
        key="$(_gpgcs_key "$key")"
        [[ -z "$key" ]] && continue
        val="$(_gpgcs_val "$val")"
        result+="entry1.${key} ${val}"$'\n'
    done

    result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
