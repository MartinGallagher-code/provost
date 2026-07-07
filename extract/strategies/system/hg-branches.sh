#!/bin/bash
## Name: hg-branches
## Description: Extract branch rows from `hg branches`
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/hg-branches/basic.txt

# `hg branches` prints one line per branch:
#   `default                  18:2f8a1c9b4d5e`
#   `stable                   15:0f9e8d7c6b5a (inactive)`
# The distinctive token is the changeset `rev:hexhash` (a decimal revision, a
# colon, then a >=6 hex node id). Emit ONE record per branch (name, rev, hash).
# Detection keys narrowly on that token so it declines apt-list/dnf-list
# (version strings like `2:9.0.1378-2` are not `NNN:hexhash`), vmstat and dstat.

_hgbr_san () { local v="$1"; v="${v//$'\t'/_}"; v="${v// /_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line hit=0
    while IFS= read -r line; do
        # Line: name, whitespace, then a `NNN:hexhash` changeset token.
        if [[ "$line" =~ ^[^[:space:]]+[[:space:]]+[0-9]+:[0-9a-f]{6,}([[:space:]]|$) ]]; then
            hit=1; break
        fi
    done <<< "$text"
    [[ $hit -eq 1 ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line name rest tok rev hash
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        name="${line%%[[:space:]]*}"
        rest="${line#"$name"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"   # ltrim to changeset token
        tok="${rest%%[[:space:]]*}"               # NNN:hexhash
        [[ "$tok" =~ ^([0-9]+):([0-9a-f]{6,})$ ]] || continue
        rev="${tok%%:*}"
        hash="${tok#*:}"
        entry=$((entry + 1))
        result+="entry${entry}.name $(_hgbr_san "$name")"$'\n'
        result+="entry${entry}.rev ${rev}"$'\n'
        result+="entry${entry}.hash ${hash}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
