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
        if _dnsrr_line "$line"; then
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
    local name ttl class type rdata
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == \;* ]] && continue
        _dnsrr_line "$line" || continue
        name="${BASH_REMATCH[1]}"
        ttl="${BASH_REMATCH[2]}"
        class="${BASH_REMATCH[3]}"
        type="${BASH_REMATCH[4]}"
        rdata="${BASH_REMATCH[5]}"
        rdata="${rdata%"${rdata##*[![:space:]]}"}"
        rdata="${rdata//$'\t'/ }"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.ttl ${ttl}"$'\n'
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
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
