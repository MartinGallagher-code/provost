#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: pv-records
## Description: `PV <dev> VG <vg> <fmt> [<size info>]` physical-volume lines (pvscan) -> pv/vg/format/size rows — hint-routed
## Version: 1.0
## Priority: 48
## Sample: samples/pv-records/basic.txt

# `pvscan` prints one physical volume per line as keyword/value pairs plus a
# format token and a bracketed size:
#
#   PV /dev/sda2   VG vg0             lvm2 [<931.51 GiB / 128.00 GiB free]
#   Total: 3 [<2.73 TiB] / in use: 3 [<2.73 TiB] / in no VG: 0 [0]
#
# The reviewer: "it's just a table." One row per PV, the keywords become the
# column names and the brackets unwrap; the Total footer is a summary, not a
# volume, and drops:
#
#   pv          vg    format  size
#   /dev/sda2   vg0   lvm2    <931.51 GiB / 128.00 GiB free
#
# HINT-ONLY: routes on the `PV /dev/` lead via hints.tsv.

_pvr_re='^PV[[:space:]]+([^[:space:]]+)[[:space:]]+VG[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+\[(.*)\][[:space:]]*$'

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ "$s" =~ $_pvr_re ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.pv ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.vg ${BASH_REMATCH[2]}"$'\n'
        result+="entry${entry}.format ${BASH_REMATCH[3]}"$'\n'
        result+="entry${entry}.size ${BASH_REMATCH[4]}"$'\n'
    done <<< "$text"
    [[ $entry -ge 1 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
