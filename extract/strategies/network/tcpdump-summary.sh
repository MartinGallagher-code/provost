#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: tcpdump-summary
## Description: Extract packet summaries from `tcpdump` line-summary output
## Version: 1.0
## Priority: 26
## Sample: samples/tcpdump-summary/basic.txt

# `tcpdump` (default summary mode) prints a `verbose output suppressed` banner
# and a `listening on ...` line, then one line per packet:
#   14:22:31.482910 IP 192.168.1.24.51234 > 93.184.216.34.443: Flags [S], ... length 0
# We emit one record per packet (time, src, dst, flags, length), skipping the
# banner / listening lines.

# Strip a Flags token like `[S.],` down to `S.`.
_tcpdump_flags () {
    local f="$1"
    f="${f#[}"; f="${f%%]*}"
    printf '%s' "${f:-NONE}"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *"tcpdump: verbose output suppressed"* ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        # Packet lines begin with an HH:MM:SS timestamp.
        case "${f[0]}" in
            [0-9][0-9]:[0-9][0-9]:[0-9][0-9]*) ;;
            *) continue ;;
        esac

        local time="${f[0]}" src="" dst="" flags="NONE" length="NONE"
        local i=0
        # src / dst straddle the ">" arrow: <src> > <dst>:
        for ((i=0; i<${#f[@]}; i++)); do
            case "${f[$i]}" in
                ">")     src="${f[$((i-1))]}"; dst="${f[$((i+1))]%:}" ;;
                Flags)   flags=$(_tcpdump_flags "${f[$((i+1))]}") ;;
                length)  length="${f[$((i+1))]}" ;;
            esac
        done

        n=$((n + 1))
        result+="entry${n}.time ${time}"$'\n'
        result+="entry${n}.src ${src:-NONE}"$'\n'
        result+="entry${n}.dst ${dst:-NONE}"$'\n'
        result+="entry${n}.flags ${flags}"$'\n'
        result+="entry${n}.length ${length}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
