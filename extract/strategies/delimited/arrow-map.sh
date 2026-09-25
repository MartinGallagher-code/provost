#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: arrow-map
## Description: `name => target (addr)` mapping lines (ldd) -> name/target/address rows
## Version: 1.0
## Priority: 43
## Sample: samples/arrow-map/basic.txt

# ldd's mapping report — three line forms, all ending in a parenthesised
# address, the ` => ` present only when a lookup resolved somewhere else:
#
#   libssl.so.3 => /lib/x86_64-linux-gnu/libssl.so.3 (0x00007f8a2c4a1000)
#   linux-vdso.so.1 (0x00007ffd3c5fe000)
#
# The reviewer: "you could parse this a bit, even though not all of the rows
# have all of the columns." So: `name | target | address`, with target empty
# where there is no arrow. Gates: >=2 lines carry ` => `; EVERY non-blank
# line matches one of the forms; the trailing `(0x…)` hex address is the
# signature that keeps this off prose containing `=>`.
_am_arrow_re='^[[:space:]]*([^[:space:]]+)[[:space:]]+=>[[:space:]]+([^[:space:]]+)[[:space:]]+\((0x[0-9a-fA-F]+)\)$'
_am_plain_re='^[[:space:]]*([^[:space:]]+)[[:space:]]+\((0x[0-9a-fA-F]+)\)$'
_am_noaddr_re='^[[:space:]]*([^[:space:]]+)[[:space:]]+=>[[:space:]]+([^[:space:]]+)$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line arrows=0 nb=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        nb=$((nb + 1))
        if [[ "$line" =~ $_am_arrow_re || "$line" =~ $_am_noaddr_re ]]; then
            arrows=$((arrows + 1))
        elif [[ "$line" =~ $_am_plain_re ]]; then :
        else return 1; fi
    done
    [[ $nb -ge 2 && $arrows -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        local n="" t="" a=""
        if [[ "$line" =~ $_am_arrow_re ]]; then
            n="${BASH_REMATCH[1]}"; t="${BASH_REMATCH[2]}"; a="${BASH_REMATCH[3]}"
        elif [[ "$line" =~ $_am_plain_re ]]; then
            n="${BASH_REMATCH[1]}"; a="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ $_am_noaddr_re ]]; then
            n="${BASH_REMATCH[1]}"; t="${BASH_REMATCH[2]}"
        else continue; fi
        entry=$((entry + 1))
        result+="entry${entry}.name ${n}"$'\n'
        [[ -n "$t" ]] && result+="entry${entry}.target ${t}"$'\n'
        [[ -n "$a" ]] && result+="entry${entry}.address ${a}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
