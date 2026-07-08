#!/bin/bash
## Name: csv
## Description: Extract field names and values from CSV files (comma-delimited with header row)
## Version: 2.0
## Priority: 14
## Technique: yes
## Sample: samples/csv/basic.csv

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _STRATEGY_CONFIDENCE_REASON="consistent comma count across lines"

    # Check first 5 non-empty lines for CSV characteristics
    local line_count=0
    local header_commas=0
    local with_commas=0
    local matching=0
    local _tmp
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        # Ignore commas inside parenthesised groups — those are not CSV field
        # separators (e.g. `mount` options `(rw,nosuid,nodev)`). Counting only
        # top-level commas keeps csv from claiming such lines.
        local _sep="${_line//(*)/}"
        _tmp="${_sep//[^,]/}"
        local c=${#_tmp}
        if [[ $line_count -eq 0 ]]; then
            # First line must have commas
            [[ $c -eq 0 ]] && return 1
            # Decline colon-delimited "key: value" lines whose commas are just
            # prose inside the value (e.g. `file` output: "name: desc, more, ...").
            # A `: ` before the first comma means this belongs to colons, not csv.
            local _before="${_sep%%,*}"
            [[ "$_before" == *": "* ]] && return 1
            header_commas=$c
        fi
        if [[ $c -gt 0 ]]; then
            with_commas=$((with_commas + 1))
            local diff=$(( header_commas - c ))
            if [[ ${diff#-} -le 1 ]]; then
                matching=$((matching + 1))
            fi
        fi
        line_count=$((line_count + 1))
        [[ $line_count -ge 5 ]] && break
    done <<< "$text"
    [[ $line_count -lt 2 ]] && return 1

    # Real CSV: most lines should have commas (allow at most 1 without)
    [[ $with_commas -lt $((line_count - 1)) ]] && return 1

    # Of lines with commas, most should have consistent counts
    local threshold=3
    if [[ $with_commas -lt 3 ]]; then
        threshold=$with_commas
    fi
    [[ $matching -ge $threshold ]] && return 0
    return 1
}

_strat_csv_count_quotes () {
    local _s="$1"
    local _tmp="${_s//[^\"]/}"
    echo "${#_tmp}"
}

strategy_extract () {
    local text="$1"

    # Strip UTF-8 BOM if present (EF BB BF)
    local bom
    bom=$(printf '\xef\xbb\xbf')
    text="${text#"$bom"}"

    # Pre-process: join multi-line quoted fields
    # Lines with an odd number of quotes are continuation lines
    local processed=""
    local pending=""
    while IFS= read -r line; do
        if [[ -n "$pending" ]]; then
            pending+=" ${line}"
            # Count quotes in accumulated line
            local qcount
            qcount=$(_strat_csv_count_quotes "$pending")
            if [[ $((qcount % 2)) -eq 0 ]]; then
                processed+="${pending}"$'\n'
                pending=""
            fi
        else
            local qcount
            qcount=$(_strat_csv_count_quotes "$line")
            if [[ $((qcount % 2)) -eq 1 ]]; then
                pending="$line"
            else
                processed+="${line}"$'\n'
            fi
        fi
    done <<< "$text"
    if [[ -n "$pending" ]]; then
        processed+="${pending}"$'\n'
    fi
    # Remove empty lines
    local _cleaned=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _cleaned+="$_line"$'\n'
    done <<< "$processed"
    text="$_cleaned"

    # Parse header row for field names
    local header=""
    local _first=1
    while IFS= read -r _line; do
        if [[ $_first -eq 1 ]]; then
            header="$_line"
            _first=0
            break
        fi
    done <<< "$text"

    # Split header into fields using IFS
    local headers; headers=()
    IFS=',' read -ra headers <<< "$header"

    # Clean BOM and whitespace from header names
    local hi
    for ((hi=0; hi<${#headers[@]}; hi++)); do
        local _h="${headers[$hi]}"
        while [[ "$_h" == " "* || "$_h" == "	"* ]]; do _h="${_h#?}"; done
        while [[ "$_h" == *" " || "$_h" == *"	" ]]; do _h="${_h%?}"; done
        headers[$hi]="$_h"
    done

    # Process each data row. Each row is emitted as an indexed record group
    # (entry<N>.<column>) so the capture tidy melt renders one row per record
    # with shared columns — rather than welding every row's cells into a single
    # wide record with duplicate column names (where the format layer would even
    # drop a later row's field that repeats an earlier row's value).
    local result=""
    local row_num=0
    local rec=0
    while IFS= read -r line; do
        row_num=$((row_num + 1))
        [[ $row_num -eq 1 ]] && continue  # skip header
        [[ -z "$line" ]] && continue

        # Parse the line field by field, handling quoted fields
        local values; values=()
        local field=""
        local in_quotes=0
        local i
        for ((i=0; i<${#line}; i++)); do
            local c="${line:$i:1}"
            if [[ $in_quotes -eq 1 ]]; then
                if [[ "$c" == '"' ]]; then
                    if [[ "${line:$((i+1)):1}" == '"' ]]; then
                        field+='"'
                        ((i++))
                    else
                        in_quotes=0
                    fi
                else
                    field+="$c"
                fi
            else
                if [[ "$c" == '"' ]]; then
                    in_quotes=1
                elif [[ "$c" == ',' ]]; then
                    values+=("$field")
                    field=""
                else
                    field+="$c"
                fi
            fi
        done
        values+=("$field")

        rec=$((rec + 1))
        local j
        for ((j=0; j<${#headers[@]}; j++)); do
            local name="${headers[$j]}"
            local value="${values[$j]:-}"
            # Clean up name and value
            name="${name// /_}"
            name="${name//\"/}"
            name="${name#_}"
            name="${name%_}"
            name="${name//./_}"   # '.' would break the tidy melt's group key split
            value="${value//\"/}"
            # Trim leading/trailing whitespace (the header fields are trimmed the
            # same way above) so a ", value" delimiter's space isn't turned into a
            # leading underscore by the space->underscore step below.
            while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done
            while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done
            [[ -z "$name" ]] && continue
            [[ -z "$value" ]] && continue
            result+="entry${rec}.${name} ${value}"$'\n'
        done
    done <<< "$text"

    [[ $rec -gt 0 ]] && result+="total_entries ${rec}"$'\n'
    echo "$result"
}
