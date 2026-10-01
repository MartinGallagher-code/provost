#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: iwlist-scan
## Description: Extract wireless cells (address/essid) from `iwlist wlan0 scan`
## Version: 1.0
## Priority: 26
## Sample: samples/iwlist-scan/basic.txt

# `iwlist <iface> scan` prints "Cell NN - Address: <MAC>" blocks with indented
# ESSID/Quality/Channel lines beneath. One record per cell.

_iwlist_is_cell () {
    [[ "$1" =~ Cell\ [0-9]+\ -\ Address:\  ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if _iwlist_is_cell "$line"; then
            _STRATEGY_CONFIDENCE=95
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a addrs=() essids=() quals=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if _iwlist_is_cell "$line"; then
            entry=$((entry + 1))
            addrs[$entry]="${line##*Address: }"
            essids[$entry]=""
            quals[$entry]=""
        elif [[ $entry -ge 1 ]]; then
            case "$line" in
                *ESSID:*)
                    local e="${line#*ESSID:}"
                    e="${e#\"}"; e="${e%\"}"
                    essids[$entry]="$e" ;;
                *Quality=*)
                    local q="${line#*Quality=}"
                    q="${q%% *}"
                    quals[$entry]="$q" ;;
            esac
        fi
    done
    local i
    for ((i = 1; i <= entry; i++)); do
        local addr="${addrs[$i]}" essid="${essids[$i]}" qual="${quals[$i]}"
        result+="entry${i}.address ${addr}"$'\n'
        result+="entry${i}.essid ${essid}"$'\n'
        result+="entry${i}.quality ${qual}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
