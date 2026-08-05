#!/bin/bash
## Name: version-line
## Description: single-line version banner (hugo version, tempo/loki `NAME, version X (branch: B, …)`) -> name/version + named columns
## Version: 1.1
## Priority: 44
## Sample: samples/version-line/basic.txt

# One-line version banners, two structural forms:
#
#   A) hugo v0.128.0-a1b2c3d4 linux/amd64 BuildDate=2026-06-30T00:00:00Z
#      dagger v0.11.9 (registry.dagger.io/engine) linux/amd64
#   B) tempo, version 2.5.0 (branch: HEAD, revision: a1b2c3d4)
#      The Glorious Glasgow Haskell Compilation System, version 9.8.2
#
# The whole line used to land as one blob cell ("you didn't even try" — the
# reviewer). Form A: FIRST token is the tool name, SECOND is version-shaped
# (`v` + dotted digits); each remaining token is a `Key=value` (named column)
# or a bare token (positional A, B, …). Form B (the Prometheus family): the
# name is everything before `, version `, the next token is the version, and a
# trailing `( k: v, k: v )` group becomes one named column per pair — the
# reviewer's "version should be a column header, branch should be a column
# header, revision should be a column header":
#
#   name   version  branch  revision
#   tempo  2.5.0    HEAD    a1b2c3d4
#
# Detection: exactly ONE non-blank line. Single-line-ness is the containment —
# multi-line reports that merely OPEN with a version banner (tinymembench,
# y-cruncher, cargo tree, prometheus's 3-line build info) never match. Form B
# additionally requires the version token itself to be clean (`38,` in perl's
# `This is perl 5, version 38, subversion 2` has a trailing comma — rejected).

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
    # Form B: `NAME, version X …` — name may be multi-word (ghc).
    if [[ "$only" == *", version "* ]]; then
        local _vb_rest="${only#*, version }"
        local _vb_ver="${_vb_rest%% *}"
        [[ "$_vb_ver" =~ $_vl_ver_re ]] && { _STRATEGY_CONFIDENCE=72; return 0; }
    fi
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
    local result=""

    # Form B: `NAME, version X ( k: v, k: v )` — paren pairs become named
    # columns; any bare trailing tokens become positional columns.
    if [[ "$only" == *", version "* ]]; then
        local rest="${only#*, version }"
        local ver="${rest%% *}"
        if [[ "$ver" =~ $_vl_ver_re ]]; then
            result+="name ${only%%, version *}"$'\n'
            result+="version ${ver}"$'\n'
            [[ "$rest" == *" "* ]] && rest="${rest#* }" || rest=""
            if [[ "$rest" =~ ^\((.*)\)[[:space:]]*$ ]]; then
                # Split the paren body on `, ` into `k: v` pairs.
                local body="${BASH_REMATCH[1]}" part k v
                local -a parts=()
                IFS=',' read -ra parts <<< "$body"
                for part in "${parts[@]}"; do
                    part="${part#"${part%%[![:space:]]*}"}"
                    part="${part%"${part##*[![:space:]]}"}"
                    [[ "$part" == *": "* ]] || continue
                    k="${part%%: *}"; v="${part#*: }"
                    k="${k// /_}"
                    result+="${k} ${v}"$'\n'
                done
            elif [[ -n "$rest" ]]; then
                local pos=0 t col
                for t in $rest; do
                    col=$(printf "\\$(printf '%03o' $((65 + pos)))")
                    pos=$((pos + 1))
                    result+="${col} ${t}"$'\n'
                done
            fi
            echo "$result"
            return 0
        fi
    fi

    local -a tok=(); read -ra tok <<< "$only"
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
