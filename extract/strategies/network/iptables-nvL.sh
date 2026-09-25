#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: iptables-nvL
## Description: Extract rule rows from `iptables -nvL` per-chain tables
## Version: 1.0
## Priority: 9
## Sample: samples/iptables-nvL/basic.txt

# `iptables -nvL` prints one block per chain: a `Chain NAME (policy ...)` header,
# a column header `pkts bytes target prot opt in out source destination`, then
# one rule row per line. Emit ONE record per rule row. Keying on the `pkts bytes
# target` column header keeps this distinct from `iptables -nL`/`iptables-nat`
# (which have no pkts/bytes columns).

_iptnvl_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"Chain "* ]] || return 1
    # The pkts/bytes/target column header is unique to -nvL (verbose) listings.
    [[ "$text" == *"pkts"*"bytes"*"target"*"prot"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line
    local -a t
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        case "$line" in
            Chain\ *) continue ;;              # chain header
            *pkts*bytes*target*) continue ;;   # column header
        esac
        { _fr_tok "$line"; t=("${_FR_TOK[@]}"); }
        # Rule rows: pkts bytes target prot opt in out source destination (>=9).
        [[ ${#t[@]} -ge 9 ]] || continue
        [[ "${t[0]}" =~ ^[0-9] ]] || continue   # pkts is numeric
        [[ "${t[1]}" =~ ^[0-9] ]] || continue   # bytes is numeric
        entry=$((entry + 1))
        result+="entry${entry}.pkts ${t[0]}"$'\n'
        result+="entry${entry}.bytes ${t[1]}"$'\n'
        result+="entry${entry}.target ${t[2]}"$'\n'
        result+="entry${entry}.prot ${t[3]}"$'\n'
        result+="entry${entry}.opt ${t[4]}"$'\n'
        result+="entry${entry}.in ${t[5]}"$'\n'
        result+="entry${entry}.out ${t[6]}"$'\n'
        result+="entry${entry}.source ${t[7]}"$'\n'
        result+="entry${entry}.destination ${t[8]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
