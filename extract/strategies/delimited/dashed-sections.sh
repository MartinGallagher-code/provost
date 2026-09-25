#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: dashed-sections
## Description: "--- Section ---" banners over aligned label/value lines — one record per section
## Version: 1.0
## Priority: 20
## Sample: samples/dashed-sections/basic.txt

# The LVM-display family shape (lvdisplay, vgdisplay, pvdisplay, and any
# report that groups aligned label/value pairs under dashed banners):
#
#   --- Logical volume ---
#   LV Path                /dev/vg0/lv_root
#   LV Name                lv_root
#   --- Segments ---
#   Logical extents 0 to 51198:
#
# One entry per banner; each body line splits on the FIRST run of 2+ spaces
# into label/value. The banner text itself is kept as entryN.section so
# records of different kinds stay distinguishable after the melt.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line saw_banner=0 body=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        local t="${line#"${line%%[![:space:]]*}"}"
        if [[ "$t" =~ ^---\ [A-Za-z][A-Za-z0-9\ ]*\ ---$ ]]; then
            saw_banner=1
            continue
        fi
        # A body line after a banner: label, 2+ spaces, value.
        if [[ $saw_banner -eq 1 && "$t" == *"  "* && -n "${t%%  *}" ]]; then
            body=$((body + 1))
            if [[ $body -ge 2 ]]; then
                _STRATEGY_CONFIDENCE=82
                return 0
            fi
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1" result="" line entry=0 fields=0
    local key val t
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        t="${line#"${line%%[![:space:]]*}"}"
        t="${t%"${t##*[![:space:]]}"}"
        [[ -z "$t" ]] && continue
        if [[ "$t" =~ ^---\ ([A-Za-z][A-Za-z0-9\ ]*)\ ---$ ]]; then
            entry=$((entry + 1))
            key="${BASH_REMATCH[1]}"
            result+="entry${entry}.section ${key}"$'\n'
            fields=$((fields + 1))
            continue
        fi
        [[ $entry -eq 0 ]] && continue
        # Split on the first 2+-space run; a line with no such run is a
        # label-only line (kept with an empty value, like `lvdisplay -m`'s
        # "LV Creation host, time server1, …" wrap).
        if [[ "$t" == *"  "* ]]; then
            key="${t%%  *}"
            val="${t#"$key"}"
            val="${val#"${val%%[![:space:]]*}"}"
        else
            key="$t"
            val=""
        fi
        [[ -z "$key" ]] && continue
        key="${key// /_}"
        key="${key//$'\t'/_}"
        val="${val//$'\t'/_}"
        result+="entry${entry}.${key} ${val}"$'\n'
        fields=$((fields + 1))
    done
    [[ $fields -gt 0 && $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
