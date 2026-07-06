#!/bin/bash
## Name: aligned-columns
## Description: Extract fields from whitespace-aligned columnar output (ps, df, mount, etc.)
## Version: 2.0
## Priority: 55
## Technique: yes
## Sample: samples/aligned-columns/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Structural detection: a header row of >=2 label tokens, followed by data
    # rows with a consistent column count. This recognises the whole class of
    # whitespace-columnar tool output (ps, df, ss, iostat, netstat, top, lsblk,
    # systemctl, …) without a per-tool rule. Confidence scales with how
    # consistent the columns are, so a clean table outranks the key/value
    # parsers that would otherwise collapse it to a single row.
    local n_h=0 idx=0 data_rows=0 consistent=0 header_alpha=0 header_caps=1
    local _line
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue   # skip blank lines
        idx=$((idx + 1))
        local _toks; _toks=(); read -ra _toks <<< "$_line"
        local n=${#_toks[@]}
        if [[ $idx -eq 1 ]]; then
            n_h=$n
            [[ $n_h -lt 2 ]] && return 1
            local t
            for t in "${_toks[@]}"; do
                [[ "$t" =~ [A-Za-z] ]] && header_alpha=1
                [[ "$t" =~ [a-z] ]] && header_caps=0
            done
            # A purely numeric first line is data, not a header — bail.
            [[ $header_alpha -eq 0 ]] && return 1
            continue
        fi
        [[ $n -ge 2 ]] && data_rows=$((data_rows + 1))
        # last column may absorb trailing tokens, so allow one short
        [[ $n -ge $((n_h - 1)) ]] && consistent=$((consistent + 1))
        [[ $idx -ge 40 ]] && break
    done <<< "$text"

    [[ $data_rows -lt 1 ]] && return 1

    local conf=40
    [[ $data_rows -ge 2 ]] && conf=$((conf + 10))
    conf=$((conf + consistent * 20 / data_rows))   # column-consistency bonus (0..20)
    [[ $header_caps -eq 1 ]] && conf=$((conf + 5))  # ALL-CAPS header (ps/df/ss style)
    [[ $conf -gt 75 ]] && conf=75
    _STRATEGY_CONFIDENCE=$conf
    return 0
}

strategy_extract () {
    local text="$1"

    # Skip blank lines at the start — collect non-empty lines
    local _cleaned=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _cleaned+="$_line"$'\n'
    done <<< "$text"
    text="$_cleaned"

    local header=""
    local _first=1
    while IFS= read -r _line; do
        if [[ $_first -eq 1 ]]; then
            header="$_line"
            _first=0
            break
        fi
    done <<< "$text"

    # Normalize header whitespace using read
    local headers; headers=()
    read -ra headers <<< "$header"
    # Field names must not contain '.' (the tidy melt splits the group key on the
    # first dot: entry<N>.<field>).
    local _hi
    for ((_hi=0; _hi<${#headers[@]}; _hi++)); do
        headers[$_hi]="${headers[$_hi]//./_}"
    done

    # Emit each data line as an indexed row group (entry<N>.<field>) so the
    # capture-side tidy melt renders one row per line with shared columns,
    # rather than welding every row into a single wide record with duplicate
    # header keys (which is what a flat `<header> <value>` emission produced).
    local result=""
    local row_num=0
    local entry=0
    while IFS= read -r line; do
        row_num=$((row_num + 1))
        [[ $row_num -eq 1 ]] && continue  # skip header
        [[ -z "$line" ]] && continue

        # Normalize whitespace using read
        local values; values=()
        read -ra values <<< "$line"

        entry=$((entry + 1))
        local i
        for ((i=0; i<${#headers[@]}; i++)); do
            local name="${headers[$i]}"
            local value="${values[$i]:-}"
            [[ -z "$value" ]] && continue
            # If this is the last header and there are extra values, combine them
            if [[ $i -eq $((${#headers[@]} - 1)) && ${#values[@]} -gt ${#headers[@]} ]]; then
                local j
                for ((j=i+1; j<${#values[@]}; j++)); do
                    value+="_${values[$j]}"
                done
            fi
            result+="entry${entry}.${name} ${value}"$'\n'
        done
    done <<< "$text"

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
