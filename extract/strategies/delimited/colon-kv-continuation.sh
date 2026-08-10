#!/bin/bash
## Name: colon-kv-continuation
## Description: aligned `Key: value` list where an indented follow-on line continues the previous value (localectl status) -> key/value rows — hint-routed
## Version: 1.0
## Priority: 99
## Sample: samples/colon-kv-continuation/basic.txt

# `localectl status` (and the other `*ctl status` dumps) print a right-aligned
# `Key: value` list in which a value can spill onto an indented follow-on line:
#
#      System Locale: LANG=en_US.UTF-8
#                     LC_TIME=en_GB.UTF-8
#          VC Keymap: uk
#         X11 Layout: gb
#        X11 Variant:
#        X11 Options: terminate:ctrl_alt_bksp
#
# The reviewer: "LC_TIME should be part of the System Locale column ... simple
# key/value with colon delimiter." So the `LC_TIME=…` line folds into the
# System Locale value rather than becoming its own row:
#
#   key             value
#   System Locale   LANG=en_US.UTF-8 LC_TIME=en_GB.UTF-8
#   VC Keymap       uk
#   X11 Layout      gb
#   X11 Variant
#   X11 Options     terminate:ctrl_alt_bksp
#
# A line whose first token-run is `Name:` (the key may hold spaces; the split
# is the FIRST colon, since a colon can't appear inside the key) starts a new
# record; the value is whatever follows, possibly empty. Any other non-blank
# line is a continuation and is appended (space-joined) to the previous value.
#
# HINT-ONLY: aligned colon lists are common enough that auto-detecting this
# would steal from `colons`, so it never auto-fires — it routes via hints.tsv.

_ckc_re='^([A-Za-z][A-Za-z0-9 ._-]*):([[:space:]]+(.*))?$'

strategy_extract () {
    local text="$1" line s
    local -a keys vals
    local n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        if [[ "$s" =~ $_ckc_re ]]; then
            keys[n]="${BASH_REMATCH[1]}"
            vals[n]="${BASH_REMATCH[3]}"
            n=$((n + 1))
        else
            # A continuation line before any key has nowhere to fold — drop it.
            [[ $n -eq 0 ]] && continue
            if [[ -n "${vals[n-1]}" ]]; then
                vals[n-1]="${vals[n-1]} ${s}"
            else
                vals[n-1]="$s"
            fi
        fi
    done <<< "$text"
    # Two or more records: a lone pair is better left to the generic parsers.
    [[ $n -ge 2 ]] || return 0
    local result="" i
    for ((i = 0; i < n; i++)); do
        result+="entry$((i + 1)).key ${keys[i]}"$'\n'
        [[ -n "${vals[i]}" ]] && result+="entry$((i + 1)).value ${vals[i]}"$'\n'
    done
    result+="total_entries ${n}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
