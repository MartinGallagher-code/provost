#!/bin/bash
## Name: compiler-diagnostics
## Description: Extract file, line, column, severity, and message from GCC/Clang compiler output
## Version: 1.0
## Priority: 15
## Sample: samples/compiler-diagnostics/basic.txt

# Helper: parse a single diagnostic line in GCC/Clang format
# Format: file:line:col: severity: message
_strat_compiler_diagnostics_parse_line () {
    local line="$1"
    local num="$2"

    local file lineno col severity message

    # Parse file:line:col: severity: message using parameter expansion
    # Work backwards from known patterns
    # file is everything before :<digits>:<digits>:
    if [[ "$line" =~ ^(.*):([0-9]+):([0-9]+):[[:space:]]*([a-z]+):[[:space:]]*(.*) ]]; then
        file="${BASH_REMATCH[1]}"
        lineno="${BASH_REMATCH[2]}"
        col="${BASH_REMATCH[3]}"
        severity="${BASH_REMATCH[4]}"
        message="${BASH_REMATCH[5]}"
    fi

    # Replace spaces in message with underscores
    message="${message// /_}"

    echo "diag${num}.file ${file}"
    echo "diag${num}.line ${lineno}"
    echo "diag${num}.column ${col}"
    echo "diag${num}.severity ${severity}"
    echo "diag${num}.message ${message}"
}

# Helper: extract summary line (e.g., "2 errors generated.")
_strat_compiler_diagnostics_extract_summary () {
    local text="$1"
    local result=""

    # GCC/Clang: "N error(s) generated." or "N warning(s) generated."
    local error_count="" warning_count=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        if [[ -z "$error_count" ]] && [[ "$_line" =~ ^([0-9]+)\ error ]]; then
            error_count="${BASH_REMATCH[1]}"
        fi
        if [[ -z "$warning_count" ]] && [[ "$_line" =~ ^([0-9]+)\ warning ]]; then
            warning_count="${BASH_REMATCH[1]}"
        fi
    done <<< "$text"

    [[ -n "$error_count" ]] && result+="total_errors ${error_count}"$'\n'
    [[ -n "$warning_count" ]] && result+="total_warnings ${warning_count}"$'\n'

    echo "$result"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # GCC/Clang format: file:line:col: error|warning|note
    [[ "$text" =~ [a-zA-Z/][^:]*:[0-9]+:[0-9]+:[[:space:]]*(error|warning|note) ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local diag_num=0

    # Extract each diagnostic line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Match GCC/Clang diagnostic format
        if [[ "$line" =~ [a-zA-Z/][^:]*:[0-9]+:[0-9]+:[[:space:]]*(error|warning|note) ]]; then
            diag_num=$((diag_num + 1))
            local parsed
            parsed=$(_strat_compiler_diagnostics_parse_line "$line" "$diag_num")
            result+="$parsed"$'\n'
        fi
    done <<< "$text"

    # Extract summary
    local summary
    summary=$(_strat_compiler_diagnostics_extract_summary "$text")
    if [[ -n "$summary" ]]; then
        result+="$summary"
    fi

    echo "$result"
}
