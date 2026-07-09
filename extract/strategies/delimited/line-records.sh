#!/bin/bash
## Name: line-records
## Description: Last-resort — each line is a record of whitespace-separated fields (value lists, single-line field dumps)
## Version: 1.0
## Priority: 96
## Technique: yes
## Sample: samples/line-records/basic.txt

# The catch-all for tabular-ish output nothing more specific claims: a single
# line of fields (date, /proc/loadavg, taskset, groups) or a consistent list of
# lines (dig +short, rpm -qa, brew list). Each line becomes one record with
# columns c1..cN. Priority 96 keeps it strictly last-resort — every real parser
# runs first.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Decline structured markup (JSON / quoted key-value) — real parsers own it,
    # and this catch-all must not pollute the engine's multi-strategy merge.
    [[ "$text" == *'{'* || "$text" == *'":'* ]] && return 1

    local counts=() idx=0 hasnum=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        local _tk; _tk=(); read -ra _tk <<< "$_l"
        counts+=("${#_tk[@]}")
        [[ "$_l" =~ [0-9] ]] && hasnum=1
        [[ $idx -ge 60 ]] && break
    done <<< "$text"

    local n=${#counts[@]}
    [[ $n -lt 1 ]] && return 1

    if [[ $n -eq 1 ]]; then
        # single line: needs >=2 fields AND a number, so pure prose (e.g. "no
        # extractable content here") isn't carved into columns.
        [[ ${counts[0]} -ge 2 && $hasnum -eq 1 ]] || return 1
        _STRATEGY_CONFIDENCE=80
        return 0
    fi

    # Multi-line: a dominant modal column count means a consistent list/table
    # (git ls-files, git branch, strings, git status …). The consistency itself is
    # the structure signal, so no digit is required here — but ragged prose (which
    # has no dominant column count) is still rejected.
    local mode=0 best=0 c d k
    for c in "${counts[@]}"; do
        k=0
        for d in "${counts[@]}"; do [[ "$d" -eq "$c" ]] && k=$((k + 1)); done
        [[ $k -gt $best ]] && { best=$k; mode=$c; }
    done
    [[ $mode -ge 1 ]] || return 1
    [[ $(( best * 100 / n )) -ge 60 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        local _tk; _tk=(); read -ra _tk <<< "$_l"
        entry=$((entry + 1))
        local i
        for ((i = 0; i < ${#_tk[@]}; i++)); do
            result+="entry${entry}.$(_col_letter $((i + 1))) ${_tk[$i]}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
