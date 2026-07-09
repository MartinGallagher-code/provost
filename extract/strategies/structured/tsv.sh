#!/bin/bash
## Name: tsv
## Description: Extract field names and values from TSV files (tab-delimited with header row)
## Version: 2.0
## Priority: 14
## Technique: yes
## Sample: samples/tsv/basic.tsv

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Must have at least 2 lines
    local line_count=0
    while IFS= read -r _line; do
        line_count=$((line_count + 1))
    done <<< "$text"
    [[ $line_count -lt 2 ]] && return 1

    # First line must contain tabs
    local first_line=""
    IFS= read -r first_line <<< "$text"
    [[ "$first_line" != *"	"* ]] && return 1

    # Tab count should be consistent between header and first data row
    local header_tabs=0 data_tabs=0
    local _tmp="$first_line"
    while [[ "$_tmp" == *"	"* ]]; do
        header_tabs=$((header_tabs + 1))
        _tmp="${_tmp#*	}"
    done

    # Get second line
    local _line_num=0 second_line=""
    while IFS= read -r _line; do
        _line_num=$((_line_num + 1))
        if [[ $_line_num -eq 2 ]]; then
            second_line="$_line"
            break
        fi
    done <<< "$text"

    _tmp="$second_line"
    while [[ "$_tmp" == *"	"* ]]; do
        data_tabs=$((data_tabs + 1))
        _tmp="${_tmp#*	}"
    done

    local diff=$(( header_tabs - data_tabs ))
    [[ ${diff#-} -le 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"

    # Parse header row for field names
    local header=""
    IFS= read -r header <<< "$text"

    # Split header into fields on tabs
    local headers; headers=()
    IFS='	' read -ra headers <<< "$header"

    # Headerless TSV: if the first line already looks like data (a digit-bearing
    # field), synthesise c1..cN column names and treat every line as a record —
    # so `du` output (size <tab> path) stays one row per line instead of eating
    # row 1 as a header.
    local headerless=0 _hf
    for _hf in "${headers[@]}"; do [[ "$_hf" =~ [0-9] ]] && { headerless=1; break; }; done
    if [[ $headerless -eq 1 ]]; then
        local _n=${#headers[@]} _i
        headers=()
        for ((_i = 1; _i <= _n; _i++)); do headers+=("$(_col_letter "$_i")"); done
    fi

    # Process each data row as an indexed record group (entry<N>.<column>) so the
    # capture tidy melt renders one row per record — rather than welding every
    # row's cells into a single wide record with duplicate column names.
    local result=""
    local row_num=0
    local rec=0
    while IFS= read -r line; do
        row_num=$((row_num + 1))
        [[ $row_num -eq 1 && $headerless -eq 0 ]] && continue  # skip header
        [[ -z "$line" ]] && continue

        # Split on tabs
        local values; values=()
        IFS='	' read -ra values <<< "$line"

        rec=$((rec + 1))
        local j
        for ((j=0; j<${#headers[@]}; j++)); do
            local name="${headers[$j]}"
            local value="${values[$j]:-}"
            # Clean up name and value: replace spaces with underscores, remove quotes
            name="${name//\"}"
            name="${name// /_}"
            name="${name#_}"
            name="${name%_}"
            name="${name//./_}"   # '.' would break the tidy melt's group key split
            value="${value//\"}"
            [[ -z "$name" ]] && continue
            [[ -z "$value" ]] && continue
            result+="entry${rec}.${name} ${value}"$'\n'
        done
    done <<< "$text"

    [[ $rec -gt 0 ]] && result+="total_entries ${rec}"$'\n'
    echo "$result"
}
