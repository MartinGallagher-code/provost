#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: keytool-list
## Description: Extract keystore entries from `keytool -list`
## Version: 1.0
## Priority: 26
## Sample: samples/keytool-list/basic.txt

# `keytool -list` prints a banner then one comma-separated line per keystore
# entry:
#   mykey, Mar 01 2024, PrivateKeyEntry, A1:B2:C3:...
# i.e. alias, date, entry-type, fingerprint. Emit ONE record per entry with the
# alias, date and type (the fingerprint is dropped). Rows are identified by the
# entry-type field so banner lines never match.

_kt_trim () {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_kt_sanitize_val () {
    local v; v="$(_kt_trim "$1")"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Signature: keystore banner plus at least one recognisable entry type.
    [[ "$text" == *"Keystore type"* ]] || return 1
    [[ "$text" == *"PrivateKeyEntry"* || "$text" == *"trustedCertEntry"* \
       || "$text" == *"SecretKeyEntry"* ]] || return 1
    _STRATEGY_CONFIDENCE=95
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line typ alias date
    local -a f
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *,* ]] || continue
        { IFS=',' _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        [[ ${#f[@]} -ge 3 ]] || continue
        typ="$(_kt_trim "${f[2]}")"
        case "$typ" in
            PrivateKeyEntry|trustedCertEntry|SecretKeyEntry) ;;
            *) continue ;;
        esac
        alias="$(_kt_sanitize_val "${f[0]}")"
        date="$(_kt_sanitize_val "${f[1]}")"
        [[ -z "$alias" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.alias ${alias}"$'\n'
        result+="entry${entry}.date ${date}"$'\n'
        result+="entry${entry}.type ${typ}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
