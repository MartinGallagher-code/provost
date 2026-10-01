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
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        # trim
        _line="${_line#"${_line%%[![:space:]]*}"}"
        _line="${_line%"${_line##*[![:space:]]}"}"
        [[ -z "$_line" ]] && continue
        _nonempty=$((_nonempty + 1))
        # (guard: a record's tokens are all KEY=value — no `=` means no record;
        # lines carrying glob characters keep the original split, whose
        # pathname expansion could in principle yield `=` tokens)
        if [[ "$_line" != *=* && "$_line" != *[*?]* && "$_line" != *\[* ]]; then
            continue
        fi
        # split on commas and/or whitespace; every token must be key=value and
        # there must be at least two (a single pair per line is another strategy).
        # A comma-joined piece WITHOUT `=` inside one whitespace token
        # continues the previous value (ovs-ofctl's `priority=100,ip`: the
        # match field list, not a new pair).
        _pairs=0; _ok=1
        local _oldifs="$IFS"; IFS=$' \t'
        # shellcheck disable=SC2086
        set -- $_line
        IFS="$_oldifs"
        local _wtok _pc _pi
        for _wtok in "$@"; do
            _pi=0
            local _oldifs2="$IFS"; IFS=','
            # shellcheck disable=SC2086
            set -f; local _pcs=($_wtok); set +f
            IFS="$_oldifs2"
            for _pc in "${_pcs[@]}"; do
                _pi=$((_pi + 1))
                [[ -z "$_pc" ]] && continue
                if [[ "$_pc" =~ $_KVP_TOKEN_RE ]]; then _pairs=$((_pairs + 1))
                elif [[ $_pi -gt 1 && $_pairs -gt 0 ]]; then :
                else _ok=0; break 2; fi
            done
        done
        [[ "$_ok" -eq 1 && "$_pairs" -ge 2 ]] && _records=$((_records + 1))
    done

    # Most non-empty lines must be kv records, and there must be at least one.
    [[ $_records -ge 1 && $_records -ge $((_nonempty - _records)) ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    printf '%s\n' "$text" | awk '
        # pairs of one line -> K[1..np] / V[1..np]; 0 when a piece is not kv
        # (a comma-joined `=`-less piece continues the previous value)
        function pairs(s,   w, nw, i, pc, npc, j) {
            np = 0
            nw = split(s, w, /[ \t]+/)
            for (i = 1; i <= nw; i++) {
                if (w[i] == "") continue
                npc = split(w[i], pc, /,/)
                for (j = 1; j <= npc; j++) {
                    if (pc[j] == "") continue
                    if (pc[j] ~ /^[A-Za-z_][A-Za-z0-9_.:-]*=/) {
                        np++; eq = index(pc[j], "=")
                        K[np] = substr(pc[j], 1, eq - 1); V[np] = substr(pc[j], eq + 1)
                    } else if (j > 1 && np > 0) {
                        V[np] = V[np] "," pc[j]
                    } else return 0
                }
            }
            return (np >= 2) ? np : 0
        }
        {
            line = $0
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            if (line == "") next
            if (!pairs(line)) next
            n++
            for (i = 1; i <= np; i++) printf "entry%d.%s %s\n", n, K[i], V[i]
        }
        END { if (n > 0) printf "total_entries %d\n", n }
    '
}
