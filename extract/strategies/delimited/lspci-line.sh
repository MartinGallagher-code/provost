#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: lspci-line
## Description: `SLOT class: description` PCI device lines (lspci, lspci -nn) -> slot/class/description rows — hint-routed
## Version: 1.0
## Priority: 45
## Sample: samples/lspci-line/basic.txt

# `lspci` prints one device per line as `SLOT class: description`:
#
#   00:00.0 Host bridge: Intel Corporation 440FX - 82441FX PMC [Natoma] (rev 02)
#   00:02.0 VGA compatible controller: Cirrus Logic GD 5446
#
# and `lspci -nn` adds bracketed IDs, still `SLOT class: description`:
#
#   00:00.0 Host bridge [0600]: Intel Corporation … [8086:9b54] (rev 05)
#
# It kept each line as one opaque cell (the leading `00:00.0` colon defeats the
# generic colon parser, which also wants a letter-led key). The reviewer wants
# columns. The split is positional: the SLOT is the first whitespace token; the
# remainder is `class: description`, cut at its FIRST `": "` (any later colon —
# a `[8086:9b54]` vendor id — stays inside the description):
#
#   slot      class                    description
#   00:00.0   Host bridge              Intel Corporation 440FX …
#   00:02.0   VGA compatible controller  Cirrus Logic GD 5446
#
# HINT-ONLY: routes on the PCI slot (BDF) shape via hints.tsv.

_lspci_re='^([^:]+):[[:space:]](.+)$'

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        # An indented line means a verbose dump (lspci -vvv/-k: capability and
        # driver sub-lines under each device) — a different shape. Bail so the
        # hint falls through to that tool's own handling.
        [[ "$line" == [[:space:]]* ]] && return 0
        local slot="${line%% *}" rest="${line#* }"
        # No space (no class/desc) — not a device line; skip.
        [[ "$rest" == "$line" ]] && continue
        # Quoted fields are the machine-readable `-mm` format, not `slot class:
        # description` — bail and let its own parser handle it.
        [[ "$rest" == '"'* ]] && return 0
        local class="" desc=""
        if [[ "$rest" =~ $_lspci_re ]]; then
            class="${BASH_REMATCH[1]}"
            desc="${BASH_REMATCH[2]}"
        else
            class="$rest"
        fi
        entry=$((entry + 1))
        result+="entry${entry}.slot ${slot}"$'\n'
        result+="entry${entry}.class ${class}"$'\n'
        [[ -n "$desc" ]] && result+="entry${entry}.description ${desc}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
