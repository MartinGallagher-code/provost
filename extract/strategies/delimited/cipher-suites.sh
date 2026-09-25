#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: cipher-suites
## Description: sslscan cipher listing (`Accepted  TLSv1.2  256 bits  NAME`) -> status/protocol/bits/cipher rows
## Version: 1.0
## Priority: 39
## Sample: samples/cipher-suites/basic.txt

# SSL/TLS scanners list one cipher per line: a status word, the protocol, the
# key size as `N bits`, and the suite name:
#
#   Preferred TLSv1.3  256 bits  TLS_AES_256_GCM_SHA384
#   Accepted  TLSv1.2  256 bits  ECDHE-RSA-AES256-GCM-SHA384
#
# block-records kept only the `Version:` preamble pair and dropped every
# cipher row — the reviewer's "you missed lots of lines". The cipher block is
# the dominant table; the scan preamble (Version, Connected to, Testing …) is
# report chrome, same treatment embedded-table gives its reports:
#
#   status     protocol  bits  cipher
#   Preferred  TLSv1.3   256   TLS_AES_256_GCM_SHA384
#
# Detection needs >=3 cipher lines — the `PROTO  N bits  NAME` core is the
# signature (protocol token constrained to TLS/SSL forms so ordinary `N bits`
# prose never matches).

_cs_line_re='^[[:space:]]*([A-Za-z]+)[[:space:]]+((TLS|SSL)v[0-9.]+)[[:space:]]+([0-9]+)[[:space:]]bits[[:space:]]+([^[:space:]]+)[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ $_cs_line_re ]] && n=$((n + 1))
    done
    [[ $n -ge 3 ]] || return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ $_cs_line_re ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.status ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.protocol ${BASH_REMATCH[2]}"$'\n'
        result+="entry${entry}.bits ${BASH_REMATCH[4]}"$'\n'
        result+="entry${entry}.cipher ${BASH_REMATCH[5]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
