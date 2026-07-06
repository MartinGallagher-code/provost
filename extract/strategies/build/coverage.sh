#!/bin/bash
## Name: coverage
## Description: Extract code coverage percentages and statistics from coverage summary output
## Version: 1.0
## Priority: 15
## Sample: samples/coverage/basic.txt

# Helper: extract coverage from pytest-cov / coverage.py table format
# Format:
#   Name           Stmts   Miss  Cover
#   -----------------------------------
#   src/main.py       42      3    93%
#   TOTAL            135     15    89%
_strat_coverage_extract_table () {
    local text="$1"
    local result=""
    local in_table=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip separator lines
        if [[ "$line" =~ ^-+$ ]]; then
            in_table=1
            continue
        fi

        # Skip header line (contains "Stmts" or "Cover" as column names)
        if [[ "$line" =~ Stmts|Cover|Branch ]]; then
            in_table=1
            continue
        fi

        # Once we're in the table, parse data rows
        if [[ $in_table -eq 1 ]]; then
            local name stmts miss cover
            read -ra _arr <<< "$line"
            name="${_arr[0]}"
            stmts="${_arr[1]}"
            miss="${_arr[2]}"
            cover="${_arr[${#_arr[@]}-1]}"

            # Validate: cover should end with %
            [[ "$cover" == *"%" ]] || continue

            # Clean the filename: strip path prefix, replace / with .
            local clean_name
            if [[ "$name" == "TOTAL" ]]; then
                result+="total_statements ${stmts}"$'\n'
                result+="total_missed ${miss}"$'\n'
                result+="total_coverage ${cover}"$'\n'
            else
                # Use basename-like approach: strip directory path and extension
                clean_name="${name##*/}"
                clean_name="${clean_name%.py}"
                clean_name="${clean_name%.js}"
                clean_name="${clean_name%.ts}"
                clean_name="${clean_name%.go}"
                clean_name="${clean_name%.rs}"
                result+="${clean_name}.statements ${stmts}"$'\n'
                result+="${clean_name}.missed ${miss}"$'\n'
                result+="${clean_name}.coverage ${cover}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}

# Helper: extract coverage from lcov-style summary
# Format: "lines......: 89.2% (120 of 135 lines)"
_strat_coverage_extract_lcov () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Match lcov format: "  category......: N% (X of Y type)" (may have leading whitespace)
        if [[ "$line" =~ ^[[:space:]]*([a-z]+)[.]*:[[:space:]]*([0-9]+[.]*[0-9]*%) ]]; then
            local category="${BASH_REMATCH[1]}"
            local pct="${BASH_REMATCH[2]}"
            category="${category// /_}"
            [[ -n "$category" && -n "$pct" ]] && result+="${category}_coverage ${pct}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Detect coverage output: lines with percentage patterns near "Cover" or "coverage"
    if [[ "$text" == *[Cc][Oo][Vv][Ee][Rr]* ]]; then
        if [[ "$text" =~ [0-9]+% ]]; then
            return 0
        fi
    fi
    # Also detect lcov-style: "lines......: N%" (may have leading whitespace)
    # Use variable for regex: (^|newline) to match any line start
    local _nl=$'\n'
    local _re="(^|${_nl})[[:space:]]*[a-z]+[.]*:[[:space:]]*[0-9]+[.]*[0-9]*%"
    if [[ "$text" =~ $_re ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Try table format first (pytest-cov / coverage.py)
    if [[ "$text" =~ Stmts|Cover ]]; then
        result=$(_strat_coverage_extract_table "$text")
    fi

    # Try lcov format
    if [[ -z "$result" ]]; then
        result=$(_strat_coverage_extract_lcov "$text")
    fi

    echo "$result"
}
