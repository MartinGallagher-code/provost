#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: colon-header-members
## Description: bare `Header:` at col 0 over indented members, plus `Header: value` lines (ethtool -T) -> key/value rows — hint-routed
## Version: 1.0
## Priority: 58
## Sample: samples/colon-header-members/basic.txt

# `ethtool -T` (and similar) mix bare section headers over indented member
# lists with plain `key: value` lines:
#
#   Time stamping parameters for eth0:
#   Capabilities:
#   	hardware-transmit
#   	software-transmit
#   PTP Hardware Clock: 0
#
# The reviewer: the first line is a throw-away; `Capabilities:` is a key with
# each indented sub-row a value (so a row per member, key repeated);
# `PTP Hardware Clock: 0` is a key/value pair. →
#
#   key                  value
#   Capabilities         hardware-transmit
#   Capabilities         software-transmit
#   PTP Hardware Clock   0
#
# A bare header (colon, no value) at column 0 becomes the active key; each
# indented member below emits `header | member`. A `key: value` line emits
# itself. A bare header with NO members contributes nothing (the throw-away
# `Time stamping parameters for eth0:` — its only follower is another header),
# so it drops out. HINT-ONLY: a bare-header + indented-member mix is common
# enough (config dumps) that this routes via hints.tsv rather than auto-fire.

strategy_extract () {
    local text="$1"
    local line result="" entry=0 header=""
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" == [!$' \t']* ]]; then
            # Unindented. `key: value` (value present) → a pair; bare `key:` →
            # a section header carried onto the indented members below.
            if [[ "$line" =~ ^([A-Za-z0-9][^:]*):[[:space:]]+[^[:space:]] ]]; then
                local k="${BASH_REMATCH[1]}" v="${line#*: }"
                v="${v%"${v##*[![:space:]]}"}"
                entry=$((entry + 1))
                result+="entry${entry}.key ${k}"$'\n'
                result+="entry${entry}.value ${v}"$'\n'
                header=""
            elif [[ "$line" == *: && "${line%:}" != *:* ]]; then
                header="${line%:}"
            else
                header=""
            fi
            continue
        fi
        # Indented member under the active header.
        [[ -n "$header" ]] || continue
        local m="${line#"${line%%[![:space:]]*}"}"
        m="${m%"${m##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.key ${header}"$'\n'
        result+="entry${entry}.value ${m}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
