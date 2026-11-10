#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: lst-stat
## Description: Lustre lnet_selftest `lst stat` samples — one row per sample, group, metric and direction (avg/min/max with unit)
## Version: 1.0
## Priority: 20
## Sample: samples/lst-stat/brw-read.txt

# `lst stat GROUP...` prints, once per sampling interval and per group, a
# rates block and a bandwidth block:
#
#   [LNet Rates of servers]
#   [R] Avg: 6028     RPC/s Min: 5981     RPC/s Max: 6074     RPC/s
#   [W] Avg: 12055    RPC/s Min: 11963    RPC/s Max: 12148    RPC/s
#   [LNet Bandwidth of servers]
#   [R] Avg: 0.92     MiB/s Min: 0.91     MiB/s Max: 0.93     MiB/s
#   [W] Avg: 6028.36  MiB/s Min: 5982.13  MiB/s Max: 6074.59  MiB/s
#
# (lnet/utils/lst.c; R is what the group's nodes received, W what they sent;
# Avg is per node, Min and Max across the group's nodes.) No interval header is
# printed: a block title seen again starts the next sample. `--avg`, `--min`,
# `--max`, `--bw`, `--rate`, `--read`, `--write` print a subset, so a missing
# field is simply left out. One record per data line: sample, group, metric
# (rates / bandwidth), direction (R / W), avg, min, max, unit.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="lnet_selftest lst stat blocks ([LNet Rates|Bandwidth of GROUP])"
    [[ "$text" =~ \[LNet\ (Rates|Bandwidth)\ of\ [^]]+\] ]] || return 1
    [[ "$text" =~ \[[RW]\]\ +(Avg|Min|Max):\ +[0-9] ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line sample=1 group="" metric="" dir rest key seen=" "
    local -a t=()
    local i unit
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" =~ ^\[LNet\ (Rates|Bandwidth)\ of\ (.+)\][[:space:]]*$ ]]; then
            metric="${BASH_REMATCH[1]}"; group="${BASH_REMATCH[2]}"
            key="${metric}|${group}"
            if [[ "$seen" == *" ${key} "* ]]; then sample=$((sample + 1)); seen=" "; fi
            seen+="${key} "
            metric="$(printf '%s' "$metric" | tr 'A-Z' 'a-z')"
            continue
        fi
        [[ -n "$group" && "$line" =~ ^\[([RW])\][[:space:]]+(.*)$ ]] || continue
        dir="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
        { _fr_tok "$rest"; t=("${_FR_TOK[@]}"); }
        entry=$((entry + 1)); unit=""
        result+="entry${entry}.sample ${sample}"$'\n'
        result+="entry${entry}.group ${group}"$'\n'
        result+="entry${entry}.metric ${metric}"$'\n'
        result+="entry${entry}.direction ${dir}"$'\n'
        for ((i = 0; i + 1 < ${#t[@]}; i++)); do
            case "${t[i]}" in
                Avg:|Min:|Max:)
                    result+="entry${entry}.$(printf '%s' "${t[i]%:}" | tr 'A-Z' 'a-z') ${t[i+1]}"$'\n'
                    [[ -z "$unit" && $((i + 2)) -lt ${#t[@]} && "${t[i+2]}" == */s ]] && unit="${t[i+2]}"
                    ;;
            esac
        done
        [[ -n "$unit" ]] && result+="entry${entry}.unit ${unit}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
