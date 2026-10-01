#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: proc-filesystems
## Description: Extract supported filesystem types from /proc/filesystems
## Version: 1.0
## Priority: 9
## Sample: samples/proc-filesystems/basic.txt

# /proc/filesystems lists one filesystem per line, tab-separated: an optional
# "nodev" marker then the filesystem name:
#   nodev<TAB>sysfs
#   <TAB>ext4
# We emit one record per line with a nodev flag and the fs name.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    [[ "$text" == *"nodev"$'\t'* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        local -a f=()
        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        [[ ${#f[@]} -lt 1 ]] && continue

        local nodev="" name
        if [[ "${f[0]}" == "nodev" && ${#f[@]} -ge 2 ]]; then
            nodev="nodev"
            name="${f[1]}"
        else
            name="${f[0]}"
        fi

        n=$((n + 1))
        result+="entry${n}.nodev ${nodev}"$'\n'
        result+="entry${n}.name ${name}"$'\n'
    done

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
