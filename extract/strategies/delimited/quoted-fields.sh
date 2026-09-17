#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: quoted-fields
## Description: Space-delimited records with quoted/bracketed field grouping (access logs, quoted crontabs, audit logs)
## Version: 1.0
## Priority: 12
## Sample: samples/quoted-fields/basic.txt

# The access-log family — space-separated positional fields where "…", '…' and
# […] group a multi-word value into ONE field:
#
#   10.0.0.1 - - [11/Jul/2026:09:15:42 +0000] "GET /index.html HTTP/1.1" 200 5120 "-" "Mozilla/5.0 (X11) Gecko"
#   2026-07-11 09:15:42 INFO  "started worker, id=3" pool=default
#   0 2 * * * /usr/local/bin/backup --dst "s3://bucket/path" --note "nightly, full"
#
# No header — rows are positional, so columns are synthesised A,B,C…. A grouping
# character is STRUCTURAL only at token start (start of line or after
# whitespace): `msg="retry scheduled"` keeps its mid-token quote literal, so
# logfmt lines and quoted CSV (quotes after commas) never form spans and stay
# with their own parsers. Detection requires EVERY line to carry at least one
# grouped span and a near-constant field count — prose with an occasional quote
# varies too much to qualify.

# Split one line into _QF_FIELDS: whitespace-delimited tokens where a token
# BEGINNING with " ' or [ runs to its matching closer (spaces included), then to
# the next whitespace. _QF_QSPANS counts only the QUOTE-grouped tokens — the
# detection signature. Brackets group (a [timestamp +0000] stays one field) but
# don't qualify a line by themselves, or every bracket-tag log and aligned table
# with a [SWAP]-style cell would match.
_strat_qf_split () {
    local line="$1"
    local i c field="" close="" len=${#line}
    _QF_FIELDS=()
    _QF_QSPANS=0
    i=0
    while [[ $i -lt $len ]]; do
        c="${line:$i:1}"
        # skip inter-field whitespace
        if [[ "$c" == " " || "$c" == $'\t' ]]; then i=$((i+1)); continue; fi
        field=""
        # grouped token?
        case "$c" in
            '"') close='"'; _QF_QSPANS=$((_QF_QSPANS + 1)) ;;
            "'") close="'"; _QF_QSPANS=$((_QF_QSPANS + 1)) ;;
            '[') close=']' ;;
            *)   close="" ;;
        esac
        if [[ -n "$close" ]]; then
            i=$((i+1))
            while [[ $i -lt $len ]]; do
                c="${line:$i:1}"
                [[ "$c" == "$close" ]] && { i=$((i+1)); break; }
                field+="$c"; i=$((i+1))
            done
        fi
        # continue the token to the next whitespace (covers [x]y and plain tokens)
        while [[ $i -lt $len ]]; do
            c="${line:$i:1}"
            [[ "$c" == " " || "$c" == $'\t' ]] && break
            field+="$c"; i=$((i+1))
        done
        _QF_FIELDS+=("$field")
    done
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local _line n=0 minf=0 maxf=0 f
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        n=$((n + 1))
        _strat_qf_split "$_line"
        f=${#_QF_FIELDS[@]}
        # DNS resource records (`name 300 IN TXT "v=spf1 …"`, space- or
        # tab-separated) carry quoted strings too — they belong to dns-records.
        # Token pair (IN, <rr-type>) anywhere in the line is the tell.
        local _qi
        for ((_qi = 0; _qi + 1 < f; _qi++)); do
            if [[ "${_QF_FIELDS[$_qi]}" == "IN" ]]; then
                case "${_QF_FIELDS[$((_qi + 1))]}" in
                    A|AAAA|TXT|MX|CNAME|NS|SOA|PTR|SRV|CAA|DS|DNSKEY|RRSIG|NSEC) return 1 ;;
                esac
            fi
        done
        # every line: at least one QUOTE-grouped span and enough fields to be a
        # positional record (4-field lines like amixer's `control 'Master',0`
        # are too short to be this shape)
        [[ $_QF_QSPANS -ge 1 && $f -ge 5 ]] || return 1
        if [[ $n -eq 1 ]]; then minf=$f; maxf=$f
        else
            [[ $f -lt $minf ]] && minf=$f
            [[ $f -gt $maxf ]] && maxf=$f
        fi
        [[ $n -ge 30 ]] && break
    done <<< "$text"
    [[ $n -ge 2 ]] || return 1
    # near-constant field count (ragged tails allowed, prose is far wider)
    [[ $((maxf - minf)) -le 2 ]] || return 1
    _STRATEGY_CONFIDENCE=78
    _STRATEGY_CONFIDENCE_REASON="space-delimited records, quoted/bracketed fields, constant field count"
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 _line i val
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        _strat_qf_split "$_line"
        [[ ${#_QF_FIELDS[@]} -lt 1 ]] && continue
        entry=$((entry + 1))
        for ((i = 0; i < ${#_QF_FIELDS[@]}; i++)); do
            val="${_QF_FIELDS[$i]}"
            [[ -z "$val" ]] && continue
            result+="entry${entry}.$(_col_letter $((i + 1))) ${val}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
