#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: dns-records
## Description: BIND-style resource-record lines (name ttl class type rdata) — dig/drill answers, zone dumps
## Version: 1.0
## Priority: 8
## Sample: samples/dns-records/basic.txt

# The standard DNS presentation format every BIND-family tool prints:
#
#   example.com.   3600  IN  MX   5 mail.example.com.
#   example.com.   3600  IN  A    93.184.216.34
#
# One record per RR line, in ANY section (ANSWER/AUTHORITY/ADDITIONAL — dig
# +trace and drill outputs interleave them). `;`-comment lines are skipped.
# MX rdata splits into preference/exchange; TXT rdata drops the surrounding
# quotes; other types keep rdata verbatim as `value`.

_dnsrr_line () {
    # Matches an RR presentation line. Captures: name ttl class type rdata.
    [[ "$1" =~ ^([A-Za-z0-9_.-]+\.?)[[:space:]]+([0-9]+)[[:space:]]+(IN|CH|HS)[[:space:]]+([A-Z0-9]+)[[:space:]]+(.*)$ ]]
}

# ZONE-FILE forms (RFC 1035 master files: `named-checkzone -D`, a zone in a
# repo): the TTL may be omitted (`www  IN  A  …`, the `$TTL` default applies),
# the owner may be `@` (the origin), or omitted entirely — a line that OPENS
# with whitespace continues the previous owner. Without a TTL the type must be
# a known RR type, so `word IN WORD …` prose never reads as a record. Sets
# _DNSRR_NAME (empty = previous owner) _DNSRR_TTL _DNSRR_CLASS _DNSRR_TYPE
# _DNSRR_RDATA.
_dnsrr_types=' A AAAA NS MX CNAME SOA TXT PTR SRV CAA DS DNSKEY RRSIG NSEC NSEC3 HINFO SPF NAPTR TLSA SSHFP DNAME LOC '
_dnsrr_zone_line () {
    local _re1='^([A-Za-z0-9_.@*-]+\.?)[[:space:]]+(([0-9]+)[[:space:]]+)?(IN|CH|HS)[[:space:]]+([A-Z0-9]+)[[:space:]]+(.*)$'
    local _re2='^[[:space:]]+(([0-9]+)[[:space:]]+)?(IN|CH|HS)[[:space:]]+([A-Z0-9]+)[[:space:]]+(.*)$'
    if [[ "$1" =~ $_re1 ]]; then
        _DNSRR_NAME="${BASH_REMATCH[1]}"; _DNSRR_TTL="${BASH_REMATCH[3]}"
        _DNSRR_CLASS="${BASH_REMATCH[4]}"; _DNSRR_TYPE="${BASH_REMATCH[5]}"; _DNSRR_RDATA="${BASH_REMATCH[6]}"
    elif [[ "$1" =~ $_re2 ]]; then
        _DNSRR_NAME=""; _DNSRR_TTL="${BASH_REMATCH[2]}"
        _DNSRR_CLASS="${BASH_REMATCH[3]}"; _DNSRR_TYPE="${BASH_REMATCH[4]}"; _DNSRR_RDATA="${BASH_REMATCH[5]}"
    else
        return 1
    fi
    [[ -n "$_DNSRR_TTL" || "$_dnsrr_types" == *" $_DNSRR_TYPE "* ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line hits=0
    # PREFILTER (exact): an RR line has a whitespace-delimited IN/CH/HS class.
    [[ "$text" == *[[:space:]]IN[[:space:]]* || "$text" == *[[:space:]]CH[[:space:]]* \
       || "$text" == *[[:space:]]HS[[:space:]]* ]] || return 1
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == \;* ]] && continue
        if _dnsrr_line "$line" || _dnsrr_zone_line "$line"; then
            hits=$((hits + 1))
            if [[ $hits -ge 2 ]]; then
                _STRATEGY_CONFIDENCE=85
                return 0
            fi
        fi
    done
    # A single RR line still counts when a dig/drill section marker confirms it.
    if [[ $hits -ge 1 && "$text" == *";; ANSWER SECTION"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1" result="" line entry=0
    local name ttl class type rdata owner="" origin="" dttl="" pend=0 _t
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # A PARENTHESISED rdata (`SOA mname rname (` … `)`, dig +multiline
        # and zone files) continues over the following lines: their `;`
        # comments are annotations, their tokens join the rdata.
        if [[ $pend -eq 1 ]]; then
            line="${line%%;*}"
            _fr_tok "$line"
            for _t in "${_FR_TOK[@]}"; do rdata+=" $_t"; done
            [[ "$line" == *")"* ]] || continue
            pend=0
            _dnsrr_emit
            continue
        fi
        [[ "$line" == \;* ]] && continue
        case "$line" in
            '$ORIGIN'[[:space:]]*) _fr_tok "$line"; origin="${_FR_TOK[1]:-}"; continue ;;
            '$TTL'[[:space:]]*)    _fr_tok "$line"; dttl="${_FR_TOK[1]:-}"; continue ;;
        esac
        if _dnsrr_line "$line"; then
            name="${BASH_REMATCH[1]}"
            ttl="${BASH_REMATCH[2]}"
            class="${BASH_REMATCH[3]}"
            type="${BASH_REMATCH[4]}"
            rdata="${BASH_REMATCH[5]}"
        elif _dnsrr_zone_line "$line"; then
            name="${_DNSRR_NAME:-$owner}"; ttl="$_DNSRR_TTL"; class="$_DNSRR_CLASS"
            type="$_DNSRR_TYPE"; rdata="$_DNSRR_RDATA"
        else
            continue
        fi
        owner="$name"
        rdata="${rdata%"${rdata##*[![:space:]]}"}"
        rdata="${rdata//$'\t'/ }"
        if [[ "$rdata" == *"("* && "$rdata" != *")"* ]]; then
            pend=1; continue
        fi
        _dnsrr_emit
    done
    [[ $pend -eq 1 ]] && _dnsrr_emit
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}

# Emit the current record (name ttl class type rdata of strategy_extract).
# A joined multi-line rdata drops its `(` `)` and keeps single spaces.
_dnsrr_emit () {
    if [[ "$rdata" == *"("* ]]; then
        rdata="${rdata//(/ }"; rdata="${rdata//)/ }"
        _fr_tok "$rdata"; rdata="${_FR_TOK[*]}"
    fi
    entry=$((entry + 1))
    result+="entry${entry}.name ${name}"$'\n'
    [[ -n "$ttl" ]] && result+="entry${entry}.ttl ${ttl}"$'\n'
    # the zone directives IN EFFECT for this record ($ORIGIN / $TTL may
    # change mid-file): the origin always, the default TTL when the record
    # carries none of its own
    [[ -n "$origin" ]] && result+="entry${entry}.origin ${origin}"$'\n'
    [[ -z "$ttl" && -n "$dttl" ]] && result+="entry${entry}.default_ttl ${dttl}"$'\n'
    result+="entry${entry}.class ${class}"$'\n'
    result+="entry${entry}.type ${type}"$'\n'
    case "$type" in
        MX)
            if [[ "$rdata" =~ ^([0-9]+)[[:space:]]+(.+)$ ]]; then
                result+="entry${entry}.preference ${BASH_REMATCH[1]}"$'\n'
                result+="entry${entry}.exchange ${BASH_REMATCH[2]}"$'\n'
            else
                result+="entry${entry}.value ${rdata}"$'\n'
            fi ;;
        TXT)
            rdata="${rdata#\"}"; rdata="${rdata%\"}"
            result+="entry${entry}.value ${rdata}"$'\n' ;;
        *)
            result+="entry${entry}.value ${rdata}"$'\n' ;;
    esac
}
