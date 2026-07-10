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
    # A document is markup when it carries quoted-key `":` syntax, or when it
    # OPENS with a brace/bracket and CLOSES with the matching kind (a JSON /
    # array document). A `{` mid-line (a UUID in `vboxmanage list vms`, an
    # exabgp block opener) or a leading `[INFO]` tag is just text.
    [[ "$text" == *'":'* ]] && return 1

    local nb=0 first="" last="" _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        [[ $nb -eq 1 ]] && first="$_l"
        last="$_l"
        [[ $nb -ge 200 ]] && break
    done <<< "$text"
    if [[ "$first" =~ ^[[:space:]]*[\{\[] ]]; then
        local _lt="${last%"${last##*[![:space:]]}"}"
        [[ "$_lt" == *'}' || "$_lt" == *']' || "$_lt" == *','  ]] && return 1
    fi

    [[ $nb -ge 1 ]] || return 1

    # A lone single line is only a record when it reads like a status, not
    # prose: a single bare token (`getenforce`'s "Enforcing") or a short
    # phrase of <=3 tokens with no sentence-ending period ("gamemode is
    # active", "Signature Verified"). Anything longer ("no extractable
    # content here") is prose with no tabular structure and falls through
    # to nothing rather than a spurious 1-cell row.
    if [[ $nb -eq 1 ]]; then
        local trimmed="${first#"${first%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        local _tk; _tk=(); read -ra _tk <<< "$trimmed"
        [[ ${#_tk[@]} -gt 3 || "$trimmed" == *. ]] && return 1
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
