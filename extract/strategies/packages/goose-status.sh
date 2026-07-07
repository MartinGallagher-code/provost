#!/bin/bash
## Name: goose-status
## Description: Extract migrations from `goose status` output (skips the header + === separator)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/goose-status/basic.txt

# `goose status` prints an "Applied At   Migration" header, a "====" separator,
# then one row per migration: "<timestamp or Pending>   <migration>". The header
# and separator are skipped; the migration name is the last whitespace token and
# the applied-at value is everything before it.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"Applied At"* && "$text" == *"Migration"* ]] || return 1
    local line stripped
    while IFS= read -r line; do
        stripped="${line//[= ]/}"
        if [[ -z "$stripped" && "$line" == *=* ]]; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line stripped
    local -a t
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *"Applied At"* ]] && continue
        stripped="${line//[= ]/}"
        [[ -z "$stripped" && "$line" == *=* ]] && continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -ge 2 ]] || continue
        local last=$(( ${#t[@]} - 1 ))
        local migration="${t[$last]}"
        local applied="" i
        for ((i=0; i<last; i++)); do applied+="${t[i]}_"; done
        applied="${applied%_}"
        entry=$((entry + 1))
        result+="entry${entry}.applied_at ${applied}"$'\n'
        result+="entry${entry}.migration ${migration}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
