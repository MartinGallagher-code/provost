#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: go-struct
## Description: Go struct dumps — {Key:value Key:value ...} banners (helm/kustomize/kubectl version)
## Version: 1.0
## Priority: 12
## Sample: samples/go-struct/basic.txt

# The `%+v` rendering Go tools print for version/build info:
#   version.BuildInfo{Version:"v3.15.2", GitCommit:"a1b2c3d4", GoVersion:"go1.22.4"}
#   {Version:kustomize/v5.4.2 GitCommit:a1b2c3d4 GoOs:linux GoArch:amd64}
# One brace-wrapped struct per line, fields as `Key:value` separated by a space
# or `, `. Values may themselves contain colons (timestamps, paths), so fields
# are found by scanning for the next `<sep><Identifier>:` boundary rather than
# splitting on ':'. NOT JSON (keys are unquoted) — the `":` guard keeps any
# real JSON with the json parsers.

# Field-boundary scan shared by detect and extract. Prints `key<TAB>value` per
# field of one struct body (the text between the braces).
_gostruct_fields () {
    printf '%s' "$1" | awk '
    {
        body=$0
        while (match(body, /(^|,?[ \t]+)[A-Za-z][A-Za-z0-9_]*:/)) {
            # key starts after the separator, ends at the colon
            seg=substr(body, RSTART, RLENGTH)
            sub(/^,?[ \t]+/, "", seg)
            key=substr(seg, 1, length(seg)-1)
            rest=substr(body, RSTART+RLENGTH)
            # value runs until the next `<sep><Identifier>:` boundary (or EOL)
            if (match(rest, /,?[ \t]+[A-Za-z][A-Za-z0-9_]*:/)) {
                val=substr(rest, 1, RSTART-1); body=substr(rest, RSTART)
            } else { val=rest; body="" }
            sub(/,[ \t]*$/, "", val)
            gsub(/^"|"$/, "", val)
            if (key!="" && val!="") printf "%s\t%s\n", key, val
        }
    }'
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="brace-wrapped Key:value struct lines (Go %+v)"

    # Quoted keys mean JSON, not a Go struct dump.
    [[ "$text" == *'":'* ]] && return 1

    local nonblank=0 structs=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        [[ $nonblank -gt 5 ]] && return 1   # a banner, not a document
        # optional `pkg.Type` prefix, then {...} spanning the rest of the line
        [[ "$_l" =~ ^[[:space:]]*[A-Za-z0-9_.]*\{(.+)\}[[:space:]]*$ ]] || return 1
        local body="${BASH_REMATCH[1]}" nf
        # a leading `Key:` plus the scanner finding >=2 fields
        [[ "$body" =~ ^[A-Za-z][A-Za-z0-9_]*: ]] || return 1
        nf="$(_gostruct_fields " $body" | grep -c .)"
        [[ "$nf" -ge 2 ]] || return 1
        structs=$((structs + 1))
    done <<< "$text"

    [[ $structs -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    # Count struct lines first: one struct is a kv snapshot (plain `key value`
    # pairs -> one wide row); several are records (entry<N>.<key> groups).
    local lines=() _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        lines+=("$_l")
    done <<< "$text"

    local result="" entry=0 li kv k v
    for ((li = 0; li < ${#lines[@]}; li++)); do
        [[ "${lines[$li]}" =~ ^[[:space:]]*[A-Za-z0-9_.]*\{(.+)\}[[:space:]]*$ ]] || continue
        local body=" ${BASH_REMATCH[1]}"
        entry=$((entry + 1))
        while IFS=$'\t' read -r k v; do
            [[ -z "$k" ]] && continue
            k="${k//./_}"
            if [[ ${#lines[@]} -eq 1 ]]; then result+="${k} ${v}"$'\n'
            else result+="entry${entry}.${k} ${v}"$'\n'; fi
        done <<< "$(_gostruct_fields "$body")"
    done
    [[ ${#lines[@]} -gt 1 && $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
