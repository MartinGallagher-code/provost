#!/bin/bash
## Name: pipe-table
## Description: Extract fields from pipe-delimited tables (SQL +-+- borders or Markdown |---| separators)
## Version: 1.1
## Priority: 25
## Sample: samples/sql-result/basic.txt

# Merges sql-result and markdown-table strategies.
# Both styles emit indexed row groups: row${n}.field value — so the capture
# tidy melt renders one row per table row (was flat, no-prefix, for markdown).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=75

    # Decline `+---+` box tables — psql-table's box parser owns those (it strips
    # outer borders and drops the single-cell title banner that `aws --output
    # table` / mysql grids carry, which this flatten-parser mangles into one
    # column). This strategy keeps the Markdown `|---|` pipe-table case.
    local _bxl
    while IFS= read -r _bxl; do
        [[ "$_bxl" == *"+"* && "$_bxl" == *"---"* ]] || continue
        [[ "$_bxl" =~ ^[[:space:]]*[-+[:space:]]+$ ]] && return 1
    done <<< "$text"

    # Markdown style: must have | lines AND a |---| separator row
    if [[ "$text" == *"|"* ]]; then
        [[ "$text" =~ \|[[:space:]]*-+ ]] && return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local headers; headers=()
    local found_header=0
    local in_data=0
    local row_num=0
    local is_sql=0

    # Detect SQL style: has + border lines
    local _nl=$'\n'
    local _re_border="(^|${_nl})\+[-+]+"
    [[ "$text" =~ $_re_border ]] && is_sql=1

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip SQL border lines (start with +)
        case "$line" in
            '+'*) continue ;;
        esac

        # Skip Markdown separator rows (only in markdown mode, to avoid false-skipping
        # SQL data rows with negative numbers like "| -1 | -2 |")
        if [[ $is_sql -eq 0 && "$line" == *"|"*"-"* ]] && [[ "$line" =~ \|[[:space:]]*-+ ]]; then
            if [[ $found_header -eq 1 ]]; then
                in_data=1
            fi
            continue
        fi

        # Skip non-pipe lines (e.g., SQL footer "3 rows in set (0.00 sec)")
        [[ "$line" == *"|"* ]] || continue

        # Parse pipe-delimited row: strip leading/trailing pipe and whitespace
        local cleaned="$line"
        while [[ "$cleaned" == " "* ]]; do cleaned="${cleaned# }"; done
        [[ "$cleaned" == "|"* ]] && cleaned="${cleaned#|}"
        while [[ "$cleaned" == *" " ]]; do cleaned="${cleaned% }"; done
        [[ "$cleaned" == *"|" ]] && cleaned="${cleaned%|}"

        # Split on |
        local cells; cells=()
        local old_ifs="$IFS"
        IFS='|'
        read -ra cells <<< "$cleaned"
        IFS="$old_ifs"

        # Trim each cell
        local ci
        for ((ci=0; ci<${#cells[@]}; ci++)); do
            local _c="${cells[$ci]}"
            while [[ "$_c" == " "* ]]; do _c="${_c# }"; done
            while [[ "$_c" == *" " ]]; do _c="${_c% }"; done
            cells[$ci]="$_c"
        done

        if [[ $found_header -eq 0 ]]; then
            # First pipe row is the header
            headers=("${cells[@]}")
            found_header=1
            # SQL: borders separate header from data, so data starts immediately
            [[ $is_sql -eq 1 ]] && in_data=1
            # Markdown: wait for separator row before accepting data
        elif [[ $in_data -eq 1 ]]; then
            row_num=$((row_num + 1))
            local j
            for ((j=0; j<${#headers[@]}; j++)); do
                local name="${headers[$j]}"
                local value="${cells[$j]:-}"
                name="${name// /_}"
                name="${name//./_}"   # '.' would break the tidy melt's group split
                [[ -z "$name" ]] && continue
                [[ -z "$value" ]] && continue
                # Both styles emit indexed row groups (row<N>.<field>) so the
                # capture-side tidy melt renders one row per table row. The
                # markdown branch previously emitted flat `<field> <value>`,
                # which welded every row into a single wide record on capture.
                result+="row${row_num}.${name} ${value}"$'\n'
            done
        fi
    done <<< "$text"

    echo "$result"
}
