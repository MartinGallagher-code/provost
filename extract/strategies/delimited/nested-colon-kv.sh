#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: nested-colon-kv
## Description: indent-nested `Header:` sections over `key: value` / `key = value` / bare members (sslyze, tailscale netcheck, vulkaninfo, fwupdmgr trees) -> section/key/value rows — hint-routed
## Version: 1.1
## Priority: 47
## Sample: samples/nested-colon-kv/basic.txt

# A family of status dumps nests data under headers that end in a colon, one
# level per indent step, with `*`/`-` bullets or box-drawing tree glyphs as
# decoration:
#
#   Report:                                  fwupdmgr:  Computer
#       * UDP: true                          │
#       * DERP latency:                      ├─UEFI dbx:
#           - fra: 12.4ms  (Frankfurt)       │     Device ID:   3623...
#
# The reviewer's notes: "two/three levels of hierarchy", "some of the info is
# header, not data", "remove the lines after interpretation" (the │├─└ glyphs).
# The tidy form carries the header path down as a `section` column:
#
#   section               key    value
#   Report                UDP    true
#   Report > DERP latency fra    12.4ms (Frankfurt)
#
# Mechanics: tree glyphs (│ ├ └ ─) become spaces (indent preserved), then
# `*`/`-` bullets are stripped. A line ending in `:` with no value is a header
# pushed on an indent stack (deeper lines nest under it; a line at the same or
# shallower indent pops it). `key: value` and `key = value` lines emit under
# the current section path; a bare line with a section is a plain member
# (key only); a bare line with NO section (a banner like VULKANINFO) drops.
#
# v1.1 also accepts a header that carries NO colon at all, when the line below
# it is MORE INDENTED — `clpeak` labels its measurement groups
# `Global memory bandwidth (GBPS)` and `Single-precision compute (GFLOPS)` with
# no punctuation, and without them every group's rows are just `float`,
# `float2`, `float4` twice over with nothing to tell bandwidth from compute
# (the reviewer's "lost Global memory bandwidth"). The indent of the NEXT line
# is what distinguishes such a header from an ordinary bare member, so lines
# are normalised up front into arrays and walked with one line of lookahead.
#
# HINT-ONLY: nested colon layouts are too common to auto-fire safely.

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    # Parallel arrays as the header stack: indent depth + name.
    local -a st_ind=() st_name=()
    # Pre-normalise every line to (indent, text) so the loop can look ahead.
    local -a li_ind=() li_s=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Tree glyphs -> spaces, preserving width so indent still nests.
        local norm="${line//│/ }"
        norm="${norm//├/ }"; norm="${norm//└/ }"; norm="${norm//─/ }"
        [[ -z "${norm//[[:space:]]/}" ]] && continue
        # Indent = leading whitespace width (tabs count as one step of 8).
        local lead="${norm%%[![:space:]]*}"
        local indent=0 ch
        while [[ -n "$lead" ]]; do
            ch="${lead:0:1}"; lead="${lead:1}"
            if [[ "$ch" == $'\t' ]]; then indent=$((indent + 8)); else indent=$((indent + 1)); fi
        done
        local s0="${norm#"${norm%%[![:space:]]*}"}"
        s0="${s0%"${s0##*[![:space:]]}"}"
        # Strip a bullet AFTER measuring indent.
        s0="${s0#\* }"; s0="${s0#- }"
        [[ -z "$s0" ]] && continue
        li_ind+=("$indent"); li_s+=("$s0")
    done <<< "$text"

    local li ln=${#li_s[@]}
    for ((li = 0; li < ln; li++)); do
        local indent="${li_ind[$li]}" s="${li_s[$li]}"
        # Pop headers at this indent or deeper.
        local n=${#st_ind[@]}
        while [[ $n -gt 0 && ${st_ind[n-1]} -ge $indent ]]; do
            unset 'st_ind[n-1]' 'st_name[n-1]'
            n=$((n - 1))
        done
        # Section path = remaining stack joined with " > ".
        local section="" i
        for ((i = 0; i < n; i++)); do
            [[ -n "$section" ]] && section+=" > "
            section+="${st_name[i]}"
        done
        local key="" val=""
        if [[ "$s" == *: && "${s%:}" != *:* ]]; then
            # Bare `Header:` — push as a section.
            st_ind[n]=$indent; st_name[n]="${s%:}"
            continue
        elif [[ "$s" != *:* && "$s" != *" = "* && $indent -gt 0 ]] &&
             [[ $((li + 1)) -lt $ln && "${li_ind[$((li + 1))]:-0}" -gt "$indent" ]]; then
            # A colon-less LABEL with deeper lines under it is a header too:
            # `Global memory bandwidth (GBPS)` over its `float : 912.44` rows.
            # Nothing but the next line's indent says so, which is why this
            # needs the lookahead.
            #
            # Only when the label is ITSELF indented. A colon-less line at the
            # left margin is a banner, not a group — `VULKANINFO`, or the
            # `Computer` that roots fwupdmgr's tree — and promoting it would
            # stamp one constant value onto every row's section path.
            st_ind[n]=$indent; st_name[n]="$s"
            continue
        elif [[ "$s" =~ ^([^:=]+):[[:space:]]+(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
        elif [[ "$s" =~ ^([^:=]+)[[:space:]]=[[:space:]]+(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
        else
            # Bare member: meaningful only under a section; a bare root line
            # (a banner, a machine name) is chrome.
            [[ -z "$section" ]] && continue
            key="$s"
        fi
        key="${key%"${key##*[![:space:]]}"}"
        val="${val%"${val##*[![:space:]]}"}"
        entry=$((entry + 1))
        [[ -n "$section" ]] && result+="entry${entry}.section ${section}"$'\n'
        result+="entry${entry}.key ${key}"$'\n'
        [[ -n "$val" ]] && result+="entry${entry}.value ${val}"$'\n'
    done
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
