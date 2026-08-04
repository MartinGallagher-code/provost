#!/bin/bash
## Name: version-line
## Description: single `name vX.Y.Z …` version banner (hugo version, dagger version) -> name/version + per-token columns
## Version: 1.0
## Priority: 44
## Sample: samples/version-line/basic.txt

# One-line version banners:
#
#   hugo v0.128.0-a1b2c3d4 linux/amd64 BuildDate=2026-06-30T00:00:00Z
#   dagger v0.11.9 (registry.dagger.io/engine) linux/amd64
#
# The whole line used to land as one blob cell ("you didn't even try" — the
# reviewer). The shape is fully structural: the FIRST token is the tool name,
# the SECOND is version-shaped (`v` + dotted digits), and each remaining token
# is either a `Key=value` (its own named column) or a bare token (positional
# A, B, … column):
#
#   name   version            A            BuildDate
#   hugo   v0.128.0-a1b2c3d4  linux/amd64  2026-06-30T00:00:00Z
#
# Detection: exactly ONE non-blank line, >=3 tokens, token 2 version-shaped.
# Single-line-ness is the containment — multi-line reports that merely OPEN
# with a version banner (tinymembench, y-cruncher, cargo tree) never match.

_vl_ver_re='^v?[0-9]+\.[0-9]+(\.[0-9]+)?([.+-][A-Za-z0-9.+-]+)?$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line only="" n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        n=$((n + 1)); only="$line"
        [[ $n -gt 1 ]] && return 1
    done <<< "$text"
    [[ $n -eq 1 ]] || return 1
    local -a tok=(); read -ra tok <<< "$only"
    [[ ${#tok[@]} -ge 3 ]] || return 1
    [[ "${tok[0]}" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || return 1
    [[ "${tok[1]}" =~ $_vl_ver_re ]] || return 1
    _STRATEGY_CONFIDENCE=72
    return 0
}

strategy_extract () {
    local text="$1"
    local line only=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        only="$line"
    done <<< "$text"
    local -a tok=(); read -ra tok <<< "$only"
    local result=""
    result+="name ${tok[0]}"$'\n'
    result+="version ${tok[1]}"$'\n'
    local i pos=0 t col
    for ((i = 2; i < ${#tok[@]}; i++)); do
        t="${tok[$i]}"
        if [[ "$t" =~ ^([A-Za-z][A-Za-z0-9_]*)=(.+)$ ]]; then
            result+="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"$'\n'
        else
            # Positional letters A, B, … for unnamed tokens.
            col=$(printf "\\$(printf '%03o' $((65 + pos)))")
            pos=$((pos + 1))
            result+="${col} ${t}"$'\n'
        fi
    done
    echo "$result"
}
