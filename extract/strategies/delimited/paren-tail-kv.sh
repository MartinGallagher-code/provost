#!/bin/bash
## Name: paren-tail-kv
## Description: `name (value)` lines — key outside the parens, value inside (gem list) -> key/value rows
## Version: 1.0
## Priority: 56
## Sample: samples/paren-tail-kv/basic.txt

# `gem list` prints a name then its versions parenthesised:
#
#   bundler (2.4.22, 2.3.26)
#   minitest (5.20.0)
#   rake (13.1.0)
#
# text-lines kept each as one opaque cell. The reviewer: "simple key, value —
# key is outside the parens, value is inside the parens." The trailing
# `(…)` unwraps into the value:
#
#   key       value
#   bundler   2.4.22, 2.3.26
#   minitest  5.20.0
#
# Detection: >=2 non-blank lines, EVERY line `NAME (…)` — a token, one space,
# a parenthesised tail to end of line, and the key holds no `(`.

_ptk_re='^([^ ()]+) \((.*)\)[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_ptk_re ]] || return 1
        n=$((n + 1))
    done <<< "$text"
    [[ $n -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_ptk_re ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.key ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.value ${BASH_REMATCH[2]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
