#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: nslookup_mx
## Description: Extract MX records from `nslookup -type=mx` output
## Version: 1.0
## Priority: 8
## Sample: samples/nslookup_mx/basic.txt

# `nslookup -type=mx <domain>` prints the Server/Address banner, then one line
# per mail exchanger:
#   gmail.com   mail exchanger = 5 gmail-smtp-in.l.google.com.
# We emit one record per `mail exchanger =` line as domain / preference /
# exchange. Banner, blanks and the trailing notes are skipped. Detection keys on
# the `mail exchanger =` phrasing, which is unique to nslookup MX output.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *"mail exchanger = "* ]] && return 0
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *"mail exchanger = "* ]] || continue
        local domain="${line%%mail exchanger =*}"
        # trim trailing whitespace/tabs from the domain
        domain="${domain%%[[:space:]]}"
        local -a d=()
        { _fr_tok "$domain"; d=("${_FR_TOK[@]}"); }
        domain="${d[0]}"
        local rest="${line#*mail exchanger = }"
        local -a r=()
        { _fr_tok "$rest"; r=("${_FR_TOK[@]}"); }
        local pref="${r[0]}" exch="${r[1]}"
        entry=$((entry + 1))
        result+="entry${entry}.domain ${domain}"$'\n'
        result+="entry${entry}.preference ${pref}"$'\n'
        result+="entry${entry}.exchange ${exch}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
