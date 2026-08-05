#!/bin/bash
## Name: line-records
## Description: Last-resort — each line is a record of whitespace-separated fields (value lists, single-line field dumps)
## Version: 1.0
## Priority: 96
## Sample: samples/line-records/basic.txt

# The catch-all for tabular-ish output nothing more specific claims: a single
# line of fields (date, /proc/loadavg, taskset, groups) or a consistent list of
# lines (dig +short, rpm -qa, brew list). Each line becomes one record with
# columns c1..cN. Priority 96 keeps it strictly last-resort — every real parser
# runs first.

# A LEADING `# /path` line is a location banner (`# /home/…/ansible_collections`
# over the collection list), not a record. Narrow to a PATH content (`# /…`)
# so section titles (`# conda environments:`, `# Memory`, `# name`) that a
# real parser uses as a header are never stripped. Strategy-local: bespoke
# parsers (go mod why) read their own `# module` markers.
_lr_body () {
    local text="$1"
    if [[ "$text" == '# /'* ]]; then
        local _rest="${text#*$'\n'}"
        [[ -n "${_rest//[[:space:]]/}" ]] && { printf '%s' "$_rest"; return; }
    fi
    # A UNIFORM leading `+` on every line is target-list decoration (earthly
    # ls prints `+base`, `+build`, …) — the reviewer's "remove the + signs".
    # Only `+`: a mixed `+`/`-` lead is a diff, a `*` lead marks a selection
    # (git branch), and both must stay data.
    local _ul_ok=1 _ul_l _ul_n=0
    while IFS= read -r _ul_l; do
        [[ -z "${_ul_l//[[:space:]]/}" ]] && continue
        _ul_n=$((_ul_n + 1))
        [[ "$_ul_l" == +[!+]* ]] || { _ul_ok=0; break; }
    done <<< "$text"
    if [[ $_ul_ok -eq 1 && $_ul_n -ge 2 ]]; then
        local _ul_out=""
        while IFS= read -r _ul_l; do
            [[ -z "${_ul_l//[[:space:]]/}" ]] && { _ul_out+="$_ul_l"$'\n'; continue; }
            _ul_out+="${_ul_l#+}"$'\n'
        done <<< "$text"
        printf '%s' "${_ul_out%$'\n'}"
        return
    fi
    printf '%s' "$text"
}

strategy_detect () {
    local text="$1"
    text="$(_lr_body "$text")"
    _STRATEGY_CONFIDENCE=0

    # Decline structured markup (JSON / quoted key-value) — real parsers own it,
    # and this catch-all must not pollute the engine's multi-strategy merge.
    [[ "$text" == *'{'* || "$text" == *'":'* ]] && return 1

    # Decline a MIXED-label colon-kv block (every line `label: value`, labels
    # distinct + single-spaced + apostrophe-free, >=1 multi-word/slash label,
    # not all one digit-template) — the same union aligned-columns 1.x
    # declines, so the block falls through to `colons` for a first-colon
    # split (resolvectl's `Link 2 (eth0): yes`) instead of being carved into
    # word tokens here.
    local _kvb_ok=1 _kvb_multi=0 _kvb_l _kvb_tpl="" _kvb_tpl_same=1 _kvb_n=0 _kvb_colons=0
    local -A _kvb_seen=()
    while IFS= read -r _kvb_l; do
        [[ -z "${_kvb_l//[[:space:]]/}" ]] && continue
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
    done <<< "$text"
    # Only defer when `colons` will actually ACCEPT the block: its detection
    # needs >=40% of lines to carry a letter-led simple label (parens, Greek,
    # digit-led ranges all fail its charset). Deferring a block colons then
    # declines would leave NO winner at all (resolvectl's `Link 2 (eth0):`).
    if [[ $_kvb_n -ge 2 && $_kvb_ok -eq 1 && $_kvb_multi -eq 1 \
          && $(( _kvb_colons * 100 / _kvb_n )) -ge 40 \
          && ! ( $_kvb_tpl_same -eq 1 && "$_kvb_tpl" == *"#"* ) ]]; then
        return 1
    fi

    local counts=() idx=0 hasnum=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        local _tk; _tk=(); read -ra _tk <<< "$_l"
        counts+=("${#_tk[@]}")
        [[ "$_l" =~ [0-9] ]] && hasnum=1
        [[ $idx -ge 60 ]] && break
    done <<< "$text"

    local n=${#counts[@]}
    [[ $n -lt 1 ]] && return 1

    if [[ $n -eq 1 ]]; then
        # single line: needs >=2 fields AND a number, so pure prose (e.g. "no
        # extractable content here") isn't carved into columns.
        [[ ${counts[0]} -ge 2 && $hasnum -eq 1 ]] || return 1
        _STRATEGY_CONFIDENCE=80
        return 0
    fi

    # Multi-line: a dominant modal column count means a consistent list/table
    # (git ls-files, git branch, strings, git status …). The consistency itself is
    # the structure signal, so no digit is required here — but ragged prose (which
    # has no dominant column count) is still rejected.
    local mode=0 best=0 c d k
    for c in "${counts[@]}"; do
        k=0
        for d in "${counts[@]}"; do [[ "$d" -eq "$c" ]] && k=$((k + 1)); done
        [[ $k -gt $best ]] && { best=$k; mode=$c; }
    done
    [[ $mode -ge 1 ]] || return 1
    [[ $(( best * 100 / n )) -ge 60 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    text="$(_lr_body "$text")"
    local result="" entry=0 _l

    # COLON-STRUCTURED single-column lists (ARNs — `arn:aws:ecs:region:
    # account:cluster/name`): every line space-free with the SAME colon
    # count >=2 means the colons are field separators, not punctuation.
    # Split them into columns instead of emitting one opaque cell.
    local _cs_ok=1 _cs_first=-1 _cs_n=0
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        _cs_n=$((_cs_n + 1))
        # URLs (`https://host:port`) and bare time lists keep their colons:
        # require no `//` and an alpha-led first field.
        if [[ "$_l" == *" "* || "$_l" == *$'\t'* || "$_l" != *:*:* \
              || "$_l" == *//* || ! "$_l" =~ ^[A-Za-z] ]]; then _cs_ok=0; break; fi
        local _cs_only="${_l//[!:]/}"
        [[ $_cs_first -lt 0 ]] && _cs_first=${#_cs_only}
        [[ ${#_cs_only} -ne $_cs_first ]] && { _cs_ok=0; break; }
    done <<< "$text"
    if [[ $_cs_ok -eq 1 && $_cs_n -ge 2 && $_cs_first -ge 2 ]]; then
        while IFS= read -r _l; do
            [[ -z "${_l//[[:space:]]/}" ]] && continue
            entry=$((entry + 1))
            local _cs_i=0 _cs_part
            while [[ "$_l" == *:* ]]; do
                _cs_part="${_l%%:*}"; _l="${_l#*:}"
                _cs_i=$((_cs_i + 1))
                [[ -n "$_cs_part" ]] && result+="entry${entry}.$(_col_letter $_cs_i) ${_cs_part}"$'\n'
            done
            _cs_i=$((_cs_i + 1))
            [[ -n "$_l" ]] && result+="entry${entry}.$(_col_letter $_cs_i) ${_l}"$'\n'
        done <<< "$text"
        [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
        echo "$result"
        return 0
    fi

    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        local _tk; _tk=(); read -ra _tk <<< "$_l"
        entry=$((entry + 1))
        local i
        for ((i = 0; i < ${#_tk[@]}; i++)); do
            result+="entry${entry}.$(_col_letter $((i + 1))) ${_tk[$i]}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
