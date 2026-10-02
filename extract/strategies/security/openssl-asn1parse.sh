#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: openssl-asn1parse
## Description: openssl asn1parse element lines (offset:d=depth hl= l= prim/cons: TAG :value) -> one row per ASN.1 element
## Version: 1.0
## Priority: 20
## Sample: samples/openssl-asn1parse/basic.txt

# `openssl asn1parse` prints one line per DER element:
#
#      0:d=0  hl=4 l= 858 cons: SEQUENCE
#     10:d=3  hl=2 l=   1 prim: INTEGER           :02
#     70:d=5  hl=2 l=  13 prim: PRINTABLESTRING   :Let's Encrypt
#
# offset, depth, header length, content length (`inf` for an indefinite
# length), primitive/constructed, the tag (`cont [ 0 ]`, `OCTET STRING
# [HEX DUMP]`) and, after the first `:`, the decoded value. The `d=`/`hl=`/
# `l=` run with a `prim:`/`cons:` marker is printed by nothing else (92,
# bespoke strong signature). The generic parsers see the padded `l=   1` and
# the `:value` tail as ragged text.

_asn1_re='^[[:space:]]*([0-9]+):d=([0-9]+)[[:space:]]+hl=([0-9]+)[[:space:]]+l=[[:space:]]*([0-9]+|inf)[[:space:]]+(prim|cons):[[:space:]]*(.*)$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # PREFILTER (exact): every element line carries `:d=` and ` hl=`.
    [[ "$text" == *":d="*" hl="* ]] || return 1
    local line nb=0 hits=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        nb=$((nb + 1))
        [[ "$line" =~ $_asn1_re ]] && hits=$((hits + 1))
    done
    # >= 2 element lines making up most of the input (a leading command
    # echo or a trailing error line is allowed)
    [[ $hits -ge 2 && $(( hits * 100 / nb )) -ge $(( 70 - ${_FR_SLACK:-0} )) ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line rest tag val
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ $_asn1_re ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.offset ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.depth ${BASH_REMATCH[2]}"$'\n'
        result+="entry${entry}.header_length ${BASH_REMATCH[3]}"$'\n'
        result+="entry${entry}.length ${BASH_REMATCH[4]}"$'\n'
        result+="entry${entry}.kind ${BASH_REMATCH[5]}"$'\n'
        rest="${BASH_REMATCH[6]}"
        val=""
        if [[ "$rest" == *:* ]]; then
            tag="${rest%%:*}"; val="${rest#*:}"
        else
            tag="$rest"
        fi
        # the tag is padded to a column: collapse its runs of spaces
        _fr_tok "$tag"; tag="${_FR_TOK[*]}"
        val="${val%"${val##*[![:space:]]}"}"
        [[ -n "$tag" ]] && result+="entry${entry}.tag ${tag}"$'\n'
        [[ -n "$val" ]] && result+="entry${entry}.value ${val}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
