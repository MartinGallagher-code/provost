#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: rfkill-list
## Description: Extract radio devices and block states from `rfkill list` output
## Version: 1.0
## Priority: 26
## Sample: samples/rfkill-list/basic.txt

# `rfkill list` prints one block per radio device:
#   0: phy0: Wireless LAN
#           Soft blocked: no
#           Hard blocked: no
# The header line is `<id>: <name>: <type>`; the indented lines carry the soft
# and hard block states. Emit one record per DEVICE with id/name/type/soft/hard
# so the tidy melt renders one row per device.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    _is_json "$text" && return 1

    # Signature: a device header `<id>: <name>: <type>` AND both a
    # "Soft blocked:" and a "Hard blocked:" indented line.
    local has_header=0 has_soft=0 has_hard=0 line t
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        t="${line#"${line%%[![:space:]]*}"}"
        case "$t" in
            [0-9]*": "*": "*) has_header=1 ;;
            "Soft blocked:"*) has_soft=1 ;;
            "Hard blocked:"*) has_hard=1 ;;
        esac
    done
    [[ $has_header -eq 1 && $has_soft -eq 1 && $has_hard -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line t n=0
    local id="" name="" type="" soft="" hard=""

    _rfkill_flush () {
        [[ -z "$id" ]] && return
        n=$((n + 1))
        result+="entry${n}.id ${id}"$'\n'
        result+="entry${n}.name ${name:-unknown}"$'\n'
        result+="entry${n}.type ${type}"$'\n'
        result+="entry${n}.soft ${soft:-unknown}"$'\n'
        result+="entry${n}.hard ${hard:-unknown}"$'\n'
    }

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        t="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$t" ]] && continue

        case "$t" in
            [0-9]*": "*": "*)
                _rfkill_flush
                id="${t%%:*}"
                local rest="${t#*: }"          # "name: type"
                name="${rest%%:*}"
                type="${rest#*: }"
                soft=""; hard=""
                ;;
            "Soft blocked:"*) soft="${t#*: }" ;;
            "Hard blocked:"*) hard="${t#*: }" ;;
        esac
    done
    _rfkill_flush

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
