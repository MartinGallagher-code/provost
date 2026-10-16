#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: colon-fields
## Description: Colon-delimited records (/etc/passwd, /etc/group, getent, fstab-ish) → one row per line
## Version: 1.1
## Priority: 48
## Sample: samples/colon-fields/basic.txt

# Classic colon-delimited tables: `root:x:0:0:root:/root:/bin/bash`. Distinct from
# the `colons` key:value parser (single ` : ` per line) — here the colon is a field
# DELIMITER packed several-per-token. The discriminator: the first whitespace token
# carries >=3 colons (>=4 packed fields), which a stray timestamp like `10:15:42`
# (2 colons) never does, so mpstat/sar-style tables are not misread as colon records.

_cf_first_colons () {
    # Colons in the first whitespace-delimited token of "$1" -> _CF_N.
    local tok="${1#"${1%%[![:space:]]*}"}"   # ltrim
    tok="${tok%%[[:space:]]*}"               # first token
    # A `::` joining two names is a NAMESPACE separator inside one identifier
    # (`APT::Key::Assert-Pubkey-Algo`, `parser::tests::empty_input:`,
    # `File::Spec`), not two field delimiters — drop those before counting.
    # passwd's empty field (`1000::/home`), gpg's `pub:u:::` and a `::`
    # delimiter before a number (envoy's `ingress::0.0.0.0:8080`,
    # liquibase's `file.sql::3::author`) are not between two letters and
    # still count.
    local _ns_re='([A-Za-z_])::([A-Za-z_])'
    while [[ "$tok" =~ $_ns_re ]]; do
        tok="${tok/"${BASH_REMATCH[0]}"/${BASH_REMATCH[1]}${BASH_REMATCH[2]}}"
    done
    local nc="${tok//[^:]/}"
    _CF_N=${#nc}
}

# _cf_uniform_colons TEXT — the second way in: every non-blank line (3+, the
# first 60) carries the SAME number (2+) of colons, none followed by a blank
# (a `key: value` colon) or opening a `://` URL or a `::` namespace, no
# clock / MAC / IP:port colons and no line with a 2+-blank column gap. Fields
# that hold blanks (`keyboxd:Public Keys:/usr/lib/gnupg/keyboxd`, nmcli -t's
# `Wired connection 1:<uuid>:802-3-ethernet:enp0s3`) defeat the
# first-token test above, but a colon count that never varies is the
# delimiter itself.
_cf_uniform_colons () {
    local _u_l _u_n=0 _u_first=-1 _u_c
    local _u_clk='[0-9]:[0-5][0-9]([^0-9A-Za-z]|$)' _u_mac='[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:' _u_ipp='[0-9][.][0-9]+:[0-9]'
    _fr_lines "$1"
    for _u_l in "${_FR_LINES[@]}"; do
        [[ "${_u_l}" != *[![:space:]]* ]] && continue
        [[ "$_u_l" == *": "* || "$_u_l" == *:$'\t'* || "$_u_l" == *"://"* || "$_u_l" == *[[:alnum:]]::[[:alnum:]]* ]] && return 1
        # (a clock `06:00:00`, a MAC `00:1a:2b`, an IP:port `10.0.0.1:80`,
        # or an aligned column gap: the colons sit inside values of
        # another format)
        [[ "$_u_l" =~ $_u_clk || "$_u_l" =~ $_u_mac || "$_u_l" =~ $_u_ipp ]] && return 1
        [[ "$_u_l" == *[![:space:]]"  "*[![:space:]]* ]] && return 1
        _u_c="${_u_l//[^:]/}"
        [[ $_u_first -lt 0 ]] && _u_first=${#_u_c}
        [[ ${#_u_c} -eq $_u_first ]] || return 1
        _u_n=$((_u_n + 1))
        [[ $_u_n -ge 60 ]] && break
    done
    [[ $_u_n -ge 3 && $_u_first -ge 2 ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *'{'* || "$text" == *'":'* ]] && return 1

    local nb=0 ok=0 _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        nb=$((nb + 1))
        _cf_first_colons "$_l"
        [[ $_CF_N -ge 3 ]] && ok=$((ok + 1))
        [[ $nb -ge 60 ]] && break
    done

    if ! [[ $nb -ge 1 && $(( ok * 100 / nb )) -ge 60 ]]; then
        _cf_uniform_colons "$text" || return 1
    fi

    # Decline a uniform identifier list: every line sharing the SAME first
    # colon-field is a scheme prefix on one opaque identifier (ARNs "arn:aws:…",
    # URIs), not per-record colon fields (passwd/group, whose first field is the
    # varying record key). Splitting an ARN into arn|aws|service|… is wrong — it
    # is a single value — so let a one-column list parser take it instead.
    local _f1="" _same=1 _seen=0 _l2
    _fr_lines "$text"
    for _l2 in "${_FR_LINES[@]}"; do
        [[ "${_l2}" != *[![:space:]]* ]] && continue
        local _pre="${_l2%%:*}"
        if [[ $_seen -eq 0 ]]; then _f1="$_pre"; _seen=1
        elif [[ "$_pre" != "$_f1" ]]; then _same=0; break; fi
    done
    # (identifiers are opaque — no whitespace; gpg --with-colons `uid:…:Alice
    # Smith (work) <…>:` records share their TYPE field, carry prose fields,
    # and are real per-record colon fields)
    [[ $_seen -eq 1 && $_same -eq 1 && $nb -ge 2 && "$text" != *[[:alnum:]]" "[[:alnum:]]* ]] && return 1

    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        entry=$((entry + 1))
        local rest="$_l" i=0 field
        while [[ "$rest" == *:* ]]; do
            field="${rest%%:*}"
            rest="${rest#*:}"
            i=$((i + 1))
            result+="entry${entry}.$(_col_letter "$i") ${field}"$'\n'
        done
        i=$((i + 1))
        result+="entry${entry}.$(_col_letter "$i") ${rest}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
