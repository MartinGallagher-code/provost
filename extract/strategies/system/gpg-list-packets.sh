#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: gpg-list-packets
## Description: Extract packet fields from `gpg --list-packets` into one wide record
## Version: 1.0
## Priority: 9
## Sample: samples/gpg-list-packets/basic.txt

# `gpg --list-packets` prints `# off=.. ctb=.. tag=..` markers, `:type packet:`
# block headers, and TAB-indented `keyword value` detail lines:
#   \tversion 4, algo 1, created 1699999999, expires 0
#   \tkeyid: A1B2C3D4E5F60718
# Flatten the tab-indented detail lines into ONE wide record (`entry1.<field>
# value`). Repeated keywords are suffixed _2, _3, ... so columns stay unique.

_gpglp_name () {
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
_gpglp_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"ctb="*"tag="* ]] || return 1
    [[ "$text" == *":public key packet:"* || "$text" == *":signature packet:"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" line rest key val san count fields=0
    declare -A seen=()
    while IFS= read -r line; do
        # Only TAB-indented detail lines carry keyword/value pairs.
        [[ "$line" == $'\t'* ]] || continue
        rest="${line#"${line%%[![:space:]]*}"}"    # ltrim (drops leading tab)
        [[ -n "$rest" ]] || continue
        key="${rest%%[[:space:]]*}"                # first word
        val="${rest#"$key"}"
        val="${val#"${val%%[![:space:]]*}"}"       # ltrim value
        san="$(_gpglp_name "$key")"
        [[ -n "$san" ]] || continue
        count="${seen[$san]:-0}"
        count=$((count + 1))
        seen[$san]=$count
        [[ $count -gt 1 ]] && san="${san}_${count}"
        result+="entry1.${san} $(_gpglp_san "$val")"$'\n'
        fields=$((fields + 1))
    done <<< "$text"
    [[ $fields -gt 0 ]] && result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
