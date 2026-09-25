#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: kv-pairs
## Description: Inline key=value records — each line is a set of key=value pairs (a table row)
## Version: 1.0
## Priority: 13
## Sample: samples/kv-pairs/basic.txt

# Lines like:
#   a=1, b=2, c=3
#   a=5, b=6, c=7
# are records: each line is a set of `key=value` pairs (comma- and/or
# whitespace-separated) sharing the same keys. Emitted as entry<N>.<key> groups
# so the capture-side tidy melt turns them into one row per line with the keys
# as columns. Distinct from the `equals`/`toml`/config strategies, which handle
# ONE pair per line; this targets MULTIPLE pairs per line (priority 13, ahead of
# csv/tsv at 14 so `a=1, b=2` is not mistaken for a CSV header + data row).

# A token is a key=value pair: an identifier, '=', then a (possibly empty) value.
_KVP_TOKEN_RE='^[A-Za-z_][A-Za-z0-9_.:-]*='

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    _STRATEGY_CONFIDENCE_REASON="lines of comma/space-separated key=value pairs"

    _is_json "$text" && return 1

    local _records=0 _nonempty=0 _line _tok _pairs _ok
    while IFS= read -r _line; do
        # trim
        _line="${_line#"${_line%%[![:space:]]*}"}"
        _line="${_line%"${_line##*[![:space:]]}"}"
        [[ -z "$_line" ]] && continue
        _nonempty=$((_nonempty + 1))
        # split on commas and/or whitespace; every token must be key=value and
        # there must be at least two (a single pair per line is another strategy).
        _pairs=0; _ok=1
        local _oldifs="$IFS"; IFS=$', \t'
        # shellcheck disable=SC2086
        set -- $_line
        IFS="$_oldifs"
        for _tok in "$@"; do
            if [[ "$_tok" =~ $_KVP_TOKEN_RE ]]; then _pairs=$((_pairs + 1)); else _ok=0; break; fi
        done
        [[ "$_ok" -eq 1 && "$_pairs" -ge 2 ]] && _records=$((_records + 1))
    done <<< "$text"

    # Most non-empty lines must be kv records, and there must be at least one.
    [[ $_records -ge 1 && $_records -ge $((_nonempty - _records)) ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    printf '%s\n' "$text" | awk '
        function is_all_kv(s,   a, i, n, p) {
            n = split(s, a, /[ \t,]+/); p = 0
            for (i = 1; i <= n; i++) {
                if (a[i] == "") continue
                if (a[i] ~ /^[A-Za-z_][A-Za-z0-9_.:-]*=/) p++
                else return 0
            }
            return (p >= 2) ? p : 0
        }
        {
            line = $0
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            if (line == "") next
            if (!is_all_kv(line)) next
            n++
            m = split(line, toks, /[ \t,]+/)
            for (i = 1; i <= m; i++) {
                if (toks[i] == "") continue
                eq = index(toks[i], "=")
                k = substr(toks[i], 1, eq - 1)
                v = substr(toks[i], eq + 1)
                printf "entry%d.%s %s\n", n, k, v
            }
        }
        END { if (n > 0) printf "total_entries %d\n", n }
    '
}
