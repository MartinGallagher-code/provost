#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: sshd-t
## Description: Extract effective sshd config from `sshd -T` (lowercase `key value` per line)
## Version: 1.0
## Priority: 26
## Sample: samples/sshd-t/basic.txt

# `sshd -T` dumps the effective server config, one directive per line as
# "key value" (space-separated, all-lowercase key, NOT colon-delimited), e.g.
#   permitrootlogin no
#   ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
# Generic key/value parsers mangle the comma-lists and mis-split the values, so
# this strategy emits ONE wide record: entry1.<key> <value> for every line.

# Known sshd directive names — used only to make detection specific.
_sshdt_known=" port addressfamily listenaddress permitrootlogin pubkeyauthentication \
passwordauthentication challengeresponseauthentication kbdinteractiveauthentication \
usepam x11forwarding maxauthtries maxsessions clientaliveinterval clientalivecountmax \
loglevel ciphers macs kexalgorithms permitemptypasswords "

_sshdt_sanitize_val () {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line key nb=0 hits=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        key="${line%%[[:space:]]*}"
        # Every non-blank line must be a lowercase-alnum directive key followed by
        # a value. This immediately rejects df-h ("/dev/sda1 ...", "Filesystem ...").
        [[ "$key" =~ ^[a-z][a-z0-9]*$ ]] || return 1
        [[ "$line" == *[[:space:]]* ]] || return 1
        [[ "$_sshdt_known" == *" $key "* ]] && hits=$((hits + 1))
        nb=$((nb + 1))
    done <<< "$text"
    if [[ $nb -ge 6 && $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line key value
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        key="${line%%[[:space:]]*}"
        [[ "$key" =~ ^[a-z][a-z0-9]*$ ]] || continue
        value="${line#"$key"}"
        value="$(_sshdt_sanitize_val "$value")"
        entry=1
        result+="entry1.${key} ${value}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
