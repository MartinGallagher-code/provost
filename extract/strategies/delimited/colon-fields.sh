#!/bin/bash
## Name: colon-fields
## Description: Colon-delimited records (/etc/passwd, /etc/group, getent, fstab-ish) → one row per line
## Version: 1.0
## Priority: 48
## Technique: yes
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
    local nc="${tok//[^:]/}"
    _CF_N=${#nc}
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *'{'* || "$text" == *'":'* ]] && return 1

    local nb=0 ok=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        _cf_first_colons "$_l"
        [[ $_CF_N -ge 3 ]] && ok=$((ok + 1))
        [[ $nb -ge 60 ]] && break
    done <<< "$text"

    [[ $nb -ge 1 && $(( ok * 100 / nb )) -ge 60 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        entry=$((entry + 1))
        local rest="$_l" i=0 field
        while [[ "$rest" == *:* ]]; do
            field="${rest%%:*}"
            rest="${rest#*:}"
            i=$((i + 1))
            field="${field// /_}"
            result+="entry${entry}.c${i} ${field}"$'\n'
        done
        i=$((i + 1))
        rest="${rest// /_}"
        result+="entry${entry}.c${i} ${rest}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
