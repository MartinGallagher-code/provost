#!/bin/bash
## Name: nested-colon-kv
## Description: indent-nested `Header:` sections over `key: value` / `key = value` / bare members (sslyze, tailscale netcheck, vulkaninfo, fwupdmgr trees) -> section/key/value rows — hint-routed
## Version: 1.0
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
# HINT-ONLY: nested colon layouts are too common to auto-fire safely.

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    # Parallel arrays as the header stack: indent depth + name.
    local -a st_ind=() st_name=()
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
        local s="${norm#"${norm%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        # Strip a bullet AFTER measuring indent.
        s="${s#\* }"; s="${s#- }"
        [[ -z "$s" ]] && continue
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
    done <<< "$text"
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
