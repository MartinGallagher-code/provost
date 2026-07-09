#!/bin/bash
## Name: inline-kv
## Description: Space-separated key=value pairs on a line (id, KEY=v KEY=v ...)
## Version: 1.0
## Priority: 30
## Sample: samples/inline-kv/id.txt

# Every non-blank line is a record of >=2 space-separated `key=value` tokens —
# e.g. `id` output (`uid=1000(alice) gid=1000(alice) groups=…`). Tidied to one
# row per line with a column per key.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local nonblank=0 kvlines=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        local toks; toks=(); read -ra toks <<< "$_l"
        local n=${#toks[@]} kv=0 t
        for t in "${toks[@]}"; do [[ "$t" =~ ^[A-Za-z_][A-Za-z0-9_-]*=.+ ]] && kv=$((kv + 1)); done
        [[ $n -ge 2 && $kv -ge 2 && $(( kv * 100 / n )) -ge 60 ]] && kvlines=$((kvlines + 1))
        [[ $nonblank -ge 40 ]] && break
    done <<< "$text"

    # Every non-blank line must be inline-kv (so we don't claim prose that
    # happens to contain one `a=b`).
    [[ $nonblank -ge 1 && $kvlines -eq $nonblank ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        local toks; toks=(); read -ra toks <<< "$_l"
        entry=$((entry + 1))
        local t
        for t in "${toks[@]}"; do
            [[ "$t" =~ ^([A-Za-z_][A-Za-z0-9_-]*)=(.*)$ ]] || continue
            local k="${BASH_REMATCH[1]//./_}" v="${BASH_REMATCH[2]}"
            result+="entry${entry}.${k} ${v}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
