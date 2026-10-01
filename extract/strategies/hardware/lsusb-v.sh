#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: lsusb-v
## Description: Extract descriptor fields from `lsusb -v` into one wide record
## Version: 1.0
## Priority: 9
## Sample: samples/lsusb-v/basic.txt

# `lsusb -v` prints a large indented key/value block for a device descriptor:
#   `  bLength                18`
#   `  idVendor           0x8087 Intel Corp.`
# Flatten the descriptor into ONE wide record (`entry1.<field> value`). Repeated
# field names (they recur across nested descriptors) are suffixed _2, _3, ... so
# columns stay unique.

_lsusbv_name () {
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
_lsusbv_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"Device Descriptor:"* ]] || return 1
    [[ "$text" == *"bLength"* ]] || return 1
    [[ "$text" == *"idVendor"* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" line key val san count fields=0
    declare -A seen=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Only indented `key value` lines (skip banners like "Device Descriptor:").
        [[ "$line" =~ ^[[:space:]]+([A-Za-z][A-Za-z0-9]*)[[:space:]]+([^[:space:]].*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        san="$(_lsusbv_name "$key")"
        [[ -n "$san" ]] || continue
        count="${seen[$san]:-0}"
        count=$((count + 1))
        seen[$san]=$count
        [[ $count -gt 1 ]] && san="${san}_${count}"
        result+="entry1.${san} $(_lsusbv_san "$val")"$'\n'
        fields=$((fields + 1))
    done
    [[ $fields -gt 0 ]] && result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
