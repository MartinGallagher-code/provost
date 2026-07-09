#!/bin/bash
## Name: iostat-x
## Description: Extract per-device extended I/O stats from `iostat -x` output
## Version: 1.0
## Priority: 26
## Sample: samples/iostat-x/basic.txt

# `iostat -x` prints a `Linux ...` banner, then an `avg-cpu:` block, then an
# extended per-device table headed by a `Device` line (no trailing colon) whose
# columns include r/s, w/s, rrqm/s and the extended-only aqu-sz. We emit one
# record per DEVICE row, ignoring the banner and the avg-cpu block.

# Turn a raw column header into a safe field name (word chars only).
_iostatx_field () {
    local c="$1"
    c="${c//%/pct_}"
    c="${c//\//_per_}"
    c="${c//-/_}"
    printf '%s' "$c" | tr -c 'A-Za-z0-9_' '_' | sed 's/_\{1,\}/_/g; s/^_//; s/_$//'
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    # Require the avg-cpu block AND an extended Device header (aqu-sz + rrqm/s).
    [[ "$text" == *"avg-cpu:"* ]] || return 1
    local line seen=0
    while IFS= read -r line; do
        [[ "$line" == Device* ]] || continue
        [[ "$line" == *"rrqm/s"* && "$line" == *"aqu-sz"* ]] && seen=1
    done <<< "$text"
    [[ $seen -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0
    local -a cols=()
    local have_header=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ $have_header -eq 0 ]]; then
            [[ "$line" == Device* ]] || continue
            read -ra cols <<< "$line"
            have_header=1
            continue
        fi

        local -a vals=()
        read -ra vals <<< "$line"
        [[ ${#vals[@]} -lt 2 ]] && continue

        n=$((n + 1))
        result+="entry${n}.device ${vals[0]}"$'\n'
        local i
        for ((i=1; i<${#cols[@]}; i++)); do
            local f; f=$(_iostatx_field "${cols[$i]}")
            [[ -z "$f" ]] && continue
            result+="entry${n}.${f} ${vals[$i]:-NONE}"$'\n'
        done
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
