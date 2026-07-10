#!/bin/bash
## Name: text-lines
## Description: Absolute last resort — each non-blank line becomes a one-column record (whole line)
## Version: 1.0
## Priority: 97
## Sample: samples/text-lines/basic.txt

# The final fallback, below even line-records (p96). When no columnar structure
# exists — ragged, single-token-varying text like `strings` output or a plain
# list — the honest tidy shape is one row per line, a single column holding the
# whole line. Runs only when everything more specific has declined.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Structured markup is owned by real parsers; never wrap it line-by-line.
    [[ "$text" == *'{'* || "$text" == *'":'* ]] && return 1

    local nb=0 first="" _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        [[ $nb -eq 1 ]] && first="$_l"
        [[ $nb -ge 2 ]] && break
    done <<< "$text"

    [[ $nb -ge 1 ]] || return 1

    # A lone single line is only a record if it is a single bare token (e.g.
    # `getenforce`'s "Enforcing") — never a multi-word prose sentence like
    # "no extractable content here", which has no tabular structure and should
    # fall through to nothing rather than be carved into a spurious 1-cell row.
    if [[ $nb -eq 1 ]]; then
        local trimmed="${first#"${first%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ "$trimmed" == *[[:space:]]* ]] && return 1
    fi

    # Otherwise: >=2 non-blank lines — one row per line, single column. Runs only
    # when every more-specific parser (incl. line-records) has declined.
    _STRATEGY_CONFIDENCE=55
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        # Trim surrounding whitespace but keep the line's own spaces.
        local v="$_l"
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v%"${v##*[![:space:]]}"}"
        [[ -z "$v" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.A ${v}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
