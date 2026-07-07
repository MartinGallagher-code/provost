#!/bin/bash
## Name: pmap
## Description: Extract memory mapping rows from `pmap <pid>` output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/pmap/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: a "<pid>:  <command>" banner on line 1, mapping rows
    # whose first token is a hex address and second a size like "148K", and a
    # trailing "total <N>" footer. df-h.txt has none of these.
    local line first="" nmap=0 total=0 n=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        n=$((n + 1))
        if [[ $n -eq 1 ]]; then
            [[ "$line" =~ ^[0-9]+: ]] || return 1
            continue
        fi
        read -ra f <<< "$line"
        if [[ "${f[0]}" == "total" ]]; then
            total=1
            continue
        fi
        if [[ "${f[0]}" =~ ^[0-9a-f]+$ && "${f[1]}" =~ ^[0-9]+K?$ ]]; then
            nmap=$((nmap + 1))
        fi
    done <<< "$text"
    if [[ $nmap -ge 2 && $total -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line n=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        n=$((n + 1))
        [[ $n -eq 1 ]] && continue                 # skip PID/command banner
        read -ra f <<< "$line"
        [[ "${f[0]}" == "total" ]] && continue     # skip footer
        # mapping row: address kbytes mode mapping...  (rss column, if present,
        # sits between kbytes and mode; guard by locating the mode token).
        [[ "${f[0]}" =~ ^[0-9a-f]+$ ]] || continue
        [[ ${#f[@]} -ge 3 ]] || continue
        local address="${f[0]}" kbytes="${f[1]}"
        # Find the permission/mode token (chars from rwxsp-). It is either f[2]
        # (no rss column) or f[3] (rss column present).
        local mode="" mapping="" idx=2
        if [[ "${f[2]}" =~ ^[rwxsp-]+$ ]]; then
            mode="${f[2]}"; idx=3
        elif [[ ${#f[@]} -ge 4 && "${f[3]}" =~ ^[rwxsp-]+$ ]]; then
            mode="${f[3]}"; idx=4
        else
            mode="${f[2]}"; idx=3
        fi
        local j="$idx"
        while [[ $j -lt ${#f[@]} ]]; do
            mapping+="${f[$j]} "; j=$((j + 1))
        done
        mapping="${mapping% }"
        mapping="${mapping// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.address ${address}"$'\n'
        result+="entry${entry}.kbytes ${kbytes}"$'\n'
        result+="entry${entry}.mode ${mode}"$'\n'
        result+="entry${entry}.mapping ${mapping}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
