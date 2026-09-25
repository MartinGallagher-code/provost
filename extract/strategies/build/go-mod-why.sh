#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: go-mod-why
## Description: Extract the import path chain from `go mod why` output
## Version: 1.0
## Priority: 20
## Sample: samples/go-mod-why/basic.txt

# `go mod why` prints "# <module>" comment headers followed by the import path
# chain, one package path per line. Each non-comment path line is one record
# (single column, the path itself).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local first="" nb=0 line ok=1
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        nb=$((nb + 1))
        [[ $nb -eq 1 ]] && first="$line"
        # (early exits are exact: the verdict below needs ok=1 AND a `# `
        # first line, so either failure settles it)
        [[ $nb -eq 1 && "$first" != "# "* ]] && return 1
        # Comment headers, or single-token import paths containing '/'. Anything
        # with embedded whitespace (a real table row) disqualifies.
        if [[ "$line" == "#"* ]]; then
            continue
        elif [[ "$line" == *[[:space:]]* || "$line" != */* ]]; then
            ok=0
            return 1
        fi
    done
    [[ $nb -eq 0 ]] && return 1
    # Require the leading "# <module>" header that opens go mod why output.
    if [[ $ok -eq 1 && "$first" == "# "* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        [[ "$line" == "#"* ]] && continue
        s="$line"
        s="${s#"${s%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.A ${s}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
