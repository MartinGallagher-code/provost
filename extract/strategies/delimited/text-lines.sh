#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: text-lines
## Description: Absolute last resort — each non-blank line becomes a one-column record (whole line)
## Version: 1.1
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
          && $(( _kvb_colons * 100 / _kvb_n )) -ge $(( 40 + ${_FR_SLACK:-0} )) \
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
    # A first line that is a CLOSED bracketed tag — `[Global flags]`, `[INFO]
    # msg`, `[2026-10-01 12:00]` (no `,` `{` `"` before its `]`) — opens a
    # section or a log line, not a JSON array (`[`, `[{`, `[1, 2,`), even when
    # the last line happens to end in `}` / `]` (`{product} {default}`).
    if [[ "$first" =~ ^[[:space:]]*[\{\[] && ( $nb -eq 1 \
          || ! "$first" =~ ^[[:space:]]*\[[^]\[,{}\"]*\] ) ]]; then
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
    # Confidence 50 (catch-all tier, see extract/README.md "Confidence rubric"):
    # the lowest any detector reports, so under confidence ranking it is tried
    # LAST, yet it still clears provost's default commit threshold (50).
    _STRATEGY_CONFIDENCE=50
    return 0
}

# SINGLE-COLUMN HEADER: a one-column list whose first line is a lone label
# (`NAME`, `FILE`, `Packages` — letters only, ALL-CAPS or Titlecase) over >= 3
# lines that are all values (each opens lowercase, with a digit, `/` or `.`)
# is a headed column, not a list whose first item is the word. Sets
# _SCH_NAME (the column name) or leaves it empty. Shared shape with
# text-lines / line-records.
_sch_detect () {
    local _sl _sn=0 _sfirst=""
    _SCH_NAME=""
    _fr_lines "$1"
    for _sl in "${_FR_LINES[@]}"; do
        [[ "${_sl}" != *[![:space:]]* ]] && continue
        _sl="${_sl#"${_sl%%[![:space:]]*}"}"; _sl="${_sl%"${_sl##*[![:space:]]}"}"
        _sn=$((_sn + 1))
        if [[ $_sn -eq 1 ]]; then
            [[ "$_sl" =~ ^[A-Z][A-Za-z_]{2,}$ ]] || return 1
            [[ "$_sl" =~ ^[A-Z_]+$ || "$_sl" =~ ^[A-Z][a-z_]+$ ]] || return 1
            _sfirst="$_sl"; continue
        fi
        [[ "$_sl" =~ ^[a-z0-9/.] ]] || return 1
    done
    [[ $_sn -ge 4 ]] || return 1
    _SCH_NAME="$_sfirst"
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l _col="A" _skip=0
    if _sch_detect "$text"; then _col="$_SCH_NAME"; _skip=1; fi
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        # Trim surrounding whitespace but keep the line's own spaces.
        local v="$_l"
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v%"${v##*[![:space:]]}"}"
        [[ -z "$v" ]] && continue
        [[ $_skip -eq 1 ]] && { _skip=0; continue; }
        entry=$((entry + 1))
        result+="entry${entry}.${_col} ${v}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
