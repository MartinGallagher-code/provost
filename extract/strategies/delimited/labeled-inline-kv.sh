#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: labeled-inline-kv
## Description: Labeled inline key=value records — "name: k=v, k=v, ..." (fio disk-stats/run-status/io-depths, ip -s)
## Version: 1.0
## Priority: 29
## Sample: samples/labeled-inline-kv/basic.txt

# Records of the form `<label>: <k=v>, <k=v>, …` — a row label, a colon, then a
# comma-separated list of key=value pairs:
#
#   sda: ios=7411882/0, merge=0/0, ticks=1882044/0, in_queue=1883210, util=98.82%
#   READ: bw=482MiB/s (505MB/s), io=28.2GiB (30.3GB), run=60001-60001msec
#   IO depths : 1=0.1%, 2=0.1%, 4=0.1%, 8=0.1%, >=64=99.9%
#
# The label becomes a `name` column and each `k=v` a data column, so the whole
# block melts to one row per label. A leading section banner (`Disk stats
# (read/write):` — a `label:` with no `k=v` after it) is skipped. Distinct from
# inline-kv (no label prefix, whitespace-separated) and colons (a single
# `key: value` per line): this needs a colon-label AND >=2 comma-separated
# `key=value` pairs after it.

# Is $1 (one comma-separated part) a bare RANGE: `lo-hi`, optionally followed by
# a parenthesised second unit's `(lo-hi)`, with no `=`? fio 3.x prints one after
# each group bandwidth — the slowest and fastest job's:
#
#   READ: bw=96.1MiB/s (101MB/s), 96.1MiB/s-96.1MiB/s (101MB/s-101MB/s), io=…
#
# It belongs to the k=v before it, so it becomes that key's `_range` column.
_lik_is_range () {
    local p="$1"
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
    [[ "$p" =~ ^[0-9][^[:space:]=]*-[0-9][^[:space:]=]*( \([0-9][^[:space:]=]*-[0-9][^[:space:]=]*\))?$ ]]
}

# Echo the k=v part after the first colon of $1, or nothing if it isn't a record.
# A record: after the first ": " there are >=2 comma-separated parts each with '='.
_lik_kvpart () {
    local line="$1"
    [[ "$line" == *:* ]] || return 1
    # A label holding `=` is not a label: the first colon then sits INSIDE a
    # value (`ts=00:00 cpu=45% load=1,23` — a time, with a decimal comma
    # later), so the line is plain inline k=v, not `label: k=v, …`.
    [[ "${line%%:*}" == *=* ]] && return 1
    # ...and a first colon flanked by digits is a clock time
    # (`2026-07-10T09:12:04Z {app=…}`), not a label separator.
    [[ "$line" =~ ^[^:]*[0-9]:[0-9] ]] && return 1
    local rest="${line#*:}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [[ "$rest" == *=* ]] || return 1
    # split on comma; need >=2 parts, each containing '=' — or, right after a
    # k=v part, a bare range of it (see _lik_is_range)
    local n=0 ok=1 part prev=0 _oi="$IFS"
    IFS=','
    # shellcheck disable=SC2086
    set -- $rest
    IFS="$_oi"
    for part in "$@"; do
        [[ "${part}" != *[![:space:]]* ]] && continue
        if [[ "$part" == *=* ]]; then
            n=$((n + 1)); prev=1
        elif [[ $prev -eq 1 ]] && _lik_is_range "$part"; then
            prev=0
        else
            ok=0; break
        fi
    done
    [[ $ok -eq 1 && $n -ge 2 ]] || return 1
    printf '%s' "$rest"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="labeled inline key=value records (name: k=v, k=v, ...)"
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1

    # Records must DOMINATE — the whole block is `label: k=v, …` records, with at
    # most one non-record line (an optional leading section title like `Disk
    # stats (read/write):`). This keeps it off `key: value` snapshots (nmcli,
    # mdadm --examine) that merely contain one stray `label: k=v, k=v` line.
    local nonblank=0 records=0 _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        nonblank=$((nonblank + 1))
        _lik_kvpart "$_l" >/dev/null && records=$((records + 1))
        [[ $nonblank -ge 40 ]] && break
    done

    [[ $records -ge 1 && $records -ge $((nonblank - 1)) ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

_lik_sanitize () {
    local s="$1"
    s="${s//[^A-Za-z0-9_]/_}"
    while [[ "$s" == *__* ]]; do s="${s//__/_}"; done
    s="${s#_}"; s="${s%_}"
    printf '%s' "$s"
}

strategy_extract () {
    local text="$1" result="" entry=0 _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        local kv; kv="$(_lik_kvpart "$_l")" || continue
        local label="${_l%%:*}"
        label="${label#"${label%%[![:space:]]*}"}"; label="${label%"${label##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${label}"$'\n'
        local part key val _oi="$IFS"
        IFS=','
        # shellcheck disable=SC2086
        set -- $kv
        IFS="$_oi"
        local lastkey=""
        for part in "$@"; do
            part="${part#"${part%%[![:space:]]*}"}"; part="${part%"${part##*[![:space:]]}"}"
            if [[ "$part" != *=* ]]; then
                # a bare range right after a k=v: that key's _range column
                [[ -n "$lastkey" && -n "$part" ]] && _lik_is_range "$part" &&
                    result+="entry${entry}.${lastkey}_range ${part}"$'\n'
                lastkey=""
                continue
            fi
            # Split on the LAST '=' so a key that itself contains '=' survives
            # (fio's `>=64=99.9%` → key `>=64`, value `99.9%`); single-'=' pairs
            # (`ios=7411882/0`) are unaffected.
            key="$(_lik_sanitize "${part%=*}")"; val="${part##*=}"
            val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
            [[ -z "$key" || -z "$val" ]] && { lastkey=""; continue; }
            result+="entry${entry}.${key} ${val}"$'\n'
            lastkey="$key"
        done
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
