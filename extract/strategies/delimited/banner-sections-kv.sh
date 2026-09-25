#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: banner-sections-kv
## Description: `---=== SECTION ===---` banners over tab/colon key:value pairs (decode-dimms) -> group/key/value rows
## Version: 1.0
## Priority: 45
## Sample: samples/banner-sections-kv/basic.txt

# `decode-dimms` groups a DIMM's attributes under dash-wrapped section banners,
# each attribute a TAB-separated `key <TAB..> value` pair (the tab run is column
# alignment):
#
#   # decode-dimms version 6.0
#   Decoding EEPROM: /sys/bus/i2c/devices/i2c-0/0-0050
#   Guessing DIMM is in			bank 1
#
#   ---=== SPD EEPROM Information ===---
#   EEPROM CRC of bytes 0-125		OK (0x1B2C)
#   # of bytes written to SDRAM EEPROM	176
#   Fundamental Memory type			DDR4 SDRAM
#
#   ---=== Memory Characteristics ===---
#   Maximum module speed			2400 MHz (PC4-19200)
#
# block-records took only the one colon line and dropped every tab-separated
# pair. The tidy shape carries the banner down as a `group` column, each
# attribute a `key | value` row:
#
#   group                     key                      value
#   (empty preamble)          Decoding EEPROM          /sys/bus/i2c/devices/i2c-0/0-0050
#   SPD EEPROM Information     EEPROM CRC of bytes 0-125  OK (0x1B2C)
#   SPD EEPROM Information     # of bytes written…      176
#
# A pair is split on the FIRST tab run, or on `: ` when there is no tab. A line
# with neither — the `# decode-dimms version 6.0` title — is not a pair and is
# dropped as decoration (note the real `# of bytes …` key IS kept: it carries a
# tab, the title does not). The `---=== … ===---` banner is a section label, not
# a pair. Preamble pairs above the first banner carry an empty group.

# Dash-wrapped section banner: `---=== TEXT ===---` (>=1 dash each side, exactly
# the three-equals label run banner-groups leaves intact, but flanked by dashes
# so the two strategies never contend).
_bsk_banner_re='^[-]+===[[:space:]]+([^=]+[^=[:space:]])[[:space:]]+===[-]+$'

# Split "$1" into _BSK_KEY / _BSK_VAL on the first tab run, else on `: `.
# Returns 1 when the line holds no key/value delimiter.
_bsk_pair () {
    local l="$1"
    if [[ "$l" == *$'\t'* ]]; then
        _BSK_KEY="${l%%$'\t'*}"
        local v="${l#*$'\t'}"
        v="${v#"${v%%[![:space:]]*}"}"
        _BSK_KEY="${_BSK_KEY%"${_BSK_KEY##*[![:space:]]}"}"
        _BSK_VAL="${v%"${v##*[![:space:]]}"}"
        [[ -n "$_BSK_KEY" && -n "$_BSK_VAL" ]] || return 1
        return 0
    fi
    if [[ "$l" == *": "* ]]; then
        _BSK_KEY="${l%%: *}"
        local v="${l#*: }"
        _BSK_KEY="${_BSK_KEY%"${_BSK_KEY##*[![:space:]]}"}"
        _BSK_VAL="${v%"${v##*[![:space:]]}"}"
        [[ -n "$_BSK_KEY" && -n "$_BSK_VAL" ]] || return 1
        return 0
    fi
    return 1
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line banners=0 pairs=0 other=0
    # PREFILTER (exact): acceptance needs a banner line, which opens `-…===`.
    [[ "$text" == *-===* ]] || return 1
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ $_bsk_banner_re ]]; then banners=$((banners + 1)); continue; fi
        if _bsk_pair "$line"; then pairs=$((pairs + 1)); else other=$((other + 1)); fi
    done
    # Need real banner sectioning over kv pairs, and almost nothing loose
    # (only a title-style decoration line or two).
    [[ $banners -ge 1 && $pairs -ge 3 && $other -le 2 ]] || return 1
    _STRATEGY_CONFIDENCE=78
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 group=""
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ $_bsk_banner_re ]]; then
            group="${BASH_REMATCH[1]}"
            continue
        fi
        _bsk_pair "$line" || continue
        entry=$((entry + 1))
        result+="entry${entry}.group ${group}"$'\n'
        result+="entry${entry}.key ${_BSK_KEY}"$'\n'
        result+="entry${entry}.value ${_BSK_VAL}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
