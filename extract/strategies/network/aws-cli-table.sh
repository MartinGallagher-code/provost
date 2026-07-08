#!/bin/bash
## Name: aws-cli-table
## Description: Extract fields from AWS CLI --output table format (pipe-delimited with border lines)
## Version: 1.0
## Priority: 35
## Sample: samples/aws-cli-table/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    local _nl=$'\n'

    # Must contain a border line starting with +- (possibly after newline)
    local _re_border="(^|${_nl})\\+-"
    [[ "$text" =~ $_re_border ]] || return 1

    # Must contain pipe-delimited data rows (lines starting with |)
    local _re_pipe="(^|${_nl})\\|"
    [[ "$text" =~ $_re_pipe ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"
    local result=""

    # Collect header names from the first data row after a border line
    local headers; headers=()
    local headers_found=0
    local row_num=0
    local saw_border=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Check for border line: starts with + and contains -
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ "$trimmed" == "+"* && "$trimmed" == *"-"* ]]; then
            saw_border=1
            continue
        fi

        # Check for section header line: starts with | and contains ||
        # e.g. "|  DescribeInstances  |" or "||  DescribeInstances  ||"
        if [[ "$trimmed" == "|"* ]]; then
            # Check if this is a section header (single-cell title row)
            # Section headers typically have no internal pipe separators
            # Remove leading and trailing |
            local inner="$trimmed"
            # Strip leading pipe(s)
            while [[ "$inner" == "|"* ]]; do inner="${inner#|}"; done
            # Strip trailing pipe(s)
            while [[ "$inner" == *"|" ]]; do inner="${inner%|}"; done
            # Trim whitespace
            while [[ "$inner" == " "* ]]; do inner="${inner# }"; done
            while [[ "$inner" == *" " ]]; do inner="${inner% }"; done

            # If no pipe remains inside, this is a section header — skip it
            if [[ "$inner" != *"|"* ]]; then
                continue
            fi

            # This is a pipe-delimited data/header row
            if [[ $headers_found -eq 0 && $saw_border -eq 1 ]]; then
                # This is the header row — parse column names
                _strat_aws_cli_table_parse_cells "$trimmed"
                local ci
                for ((ci=0; ci<${#_CELLS[@]}; ci++)); do
                    local hname="${_CELLS[$ci]}"
                    # Replace spaces with underscores in header names
                    hname="${hname// /_}"
                    headers+=("$hname")
                done
                headers_found=1
                saw_border=0
                continue
            fi

            if [[ $headers_found -eq 1 ]]; then
                # Data row
                _strat_aws_cli_table_parse_cells "$trimmed"
                row_num=$((row_num + 1))
                local prefix="line${row_num}"

                local j
                for ((j=0; j<${#headers[@]}; j++)); do
                    local name="${headers[$j]}"
                    local value="${_CELLS[$j]:-}"
                    [[ -z "$name" ]] && continue
                    [[ -z "$value" ]] && continue
                    result+="${prefix}.${name} ${value}"$'\n'
                done
            fi
        fi
    done <<< "$text"

    echo "$result"
}

# Helper: parse a pipe-delimited row into _CELLS array
# Input: "| val1 | val2 | val3 |"
# Output: _CELLS=("val1" "val2" "val3")
_strat_aws_cli_table_parse_cells () {
    local row="$1"
    _CELLS=()

    # Strip leading whitespace and pipe
    while [[ "$row" == " "* ]]; do row="${row# }"; done
    [[ "$row" == "|"* ]] && row="${row#|}"
    # Strip trailing whitespace and pipe
    while [[ "$row" == *" " ]]; do row="${row% }"; done
    [[ "$row" == *"|" ]] && row="${row%|}"

    # Split on |
    local old_ifs="$IFS"
    IFS='|'
    local parts; parts=()
    read -ra parts <<< "$row"
    IFS="$old_ifs"

    local part
    for part in "${parts[@]}"; do
        # Trim leading/trailing whitespace
        while [[ "$part" == " "* ]]; do part="${part# }"; done
        while [[ "$part" == *" " ]]; do part="${part% }"; done
        _CELLS+=("$part")
    done
}
