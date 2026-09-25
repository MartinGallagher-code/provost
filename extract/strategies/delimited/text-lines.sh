#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

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

    # Decline a MIXED-label colon-kv block (every line `label: value`, labels
    # distinct + single-spaced + apostrophe-free, >=1 multi-word/slash label,
    # not all one digit-template) — the same union aligned-columns and
    # line-records decline, so the block reaches `colons` for a first-colon
    # split (resolvectl's `Link 2 (eth0): yes`) instead of landing here as
    # one-cell rows.
    local _kvb_ok=1 _kvb_multi=0 _kvb_l _kvb_tpl="" _kvb_tpl_same=1 _kvb_n=0 _kvb_colons=0
    local -A _kvb_seen=()
    _fr_lines "$text"
    for _kvb_l in "${_FR_LINES[@]}"; do
        [[ "${_kvb_l}" != *[![:space:]]* ]] && continue
        _kvb_n=$((_kvb_n + 1))
        if [[ ! "$_kvb_l" =~ ^[[:space:]]*([^:]+):[[:space:]]+[^[:space:]] ]]; then
            _kvb_ok=0; break
        fi
        local _kvbl="${BASH_REMATCH[1]}"
        _kvbl="${_kvbl#"${_kvbl%%[![:space:]]*}"}"
        _kvbl="${_kvbl%"${_kvbl##*[![:space:]]}"}"
        [[ "$_kvbl" == *"  "* || -z "$_kvbl" || "$_kvbl" == *"'"* ]] && { _kvb_ok=0; break; }
        [[ -n "${_kvb_seen[$_kvbl]:-}" ]] && { _kvb_ok=0; break; }
        _kvb_seen[$_kvbl]=1
        [[ "$_kvbl" == *" "* || "$_kvbl" == */* ]] && _kvb_multi=1
        [[ "$_kvbl" =~ ^[A-Za-z][A-Za-z0-9_\ -]*$ ]] && _kvb_colons=$((_kvb_colons + 1))
        local _kvbt="${_kvbl//[0-9]/#}"
        while [[ "$_kvbt" == *"##"* ]]; do _kvbt="${_kvbt//##/#}"; done
        if [[ -z "$_kvb_tpl" ]]; then _kvb_tpl="$_kvbt"
        elif [[ "$_kvbt" != "$_kvb_tpl" ]]; then _kvb_tpl_same=0
        fi
    done
    # Only defer when `colons` will actually ACCEPT the block: its detection
    # needs >=40% of lines to carry a letter-led simple label (parens, Greek,
    # digit-led ranges all fail its charset). Deferring a block colons then
    # declines would leave NO winner at all (resolvectl's `Link 2 (eth0):`).
    if [[ $_kvb_n -ge 2 && $_kvb_ok -eq 1 && $_kvb_multi -eq 1 \
          && $(( _kvb_colons * 100 / _kvb_n )) -ge 40 \
          && ! ( $_kvb_tpl_same -eq 1 && "$_kvb_tpl" == *"#"* ) ]]; then
        return 1
    fi

    local nb=0 first="" last="" _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        nb=$((nb + 1))
        [[ $nb -eq 1 ]] && first="$_l"
        last="$_l"
        [[ $nb -ge 200 ]] && break
    done
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
        local _tk; _tk=(); { _fr_tok "$trimmed"; _tk=("${_FR_TOK[@]}"); }
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
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        # Trim surrounding whitespace but keep the line's own spaces.
        local v="$_l"
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v%"${v##*[![:space:]]}"}"
        [[ -z "$v" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.A ${v}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
