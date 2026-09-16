#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: section-kv
## Description: `key: value` pairs where a bare `Header:` line becomes the key for the plain lines beneath it (nslookup -type=mx) -> key/value records
## Version: 1.0
## Priority: 58
## Sample: samples/section-kv/basic.txt

# Some tools mix real `key: value` pairs with a bare section header — a line
# that ends in a colon and carries NO value — over plain lines that belong to
# it. `nslookup -type=mx` is the shape the reviewer named:
#
#   Server:		127.0.0.53
#   Address:	127.0.0.53#53
#
#   Non-authoritative answer:
#   gmail.com	mail exchanger = 5 gmail-smtp-in.l.google.com.
#   gmail.com	mail exchanger = 10 alt1.gmail-smtp-in.l.google.com.
#
#   Authoritative answers can be found from:
#
# The reviewer's note: "each of the gmail.com entries should have
# `Non-authoritative answer:` as their key for the key/value pair." So the bare
# header is carried DOWN as the key of every plain line beneath it, and the
# ordinary `key: value` lines above emit as themselves — one `key | value`
# table:
#
#   Server                    127.0.0.53
#   Address                   127.0.0.53#53
#   Non-authoritative answer  gmail.com mail exchanger = 5 gmail-smtp-in.l.google.com.
#   Non-authoritative answer  gmail.com mail exchanger = 10 alt1.gmail-smtp-in.l.google.com.
#
# A bare header with NO plain lines beneath it (its followers are all their own
# `key: value` pairs — plain `nslookup`, whose `Name:`/`Address:` sit under the
# same `Non-authoritative answer:` banner) contributes nothing and drops out,
# so this leaves that colon-list to the `colons` fallback untouched.
#
# Records are entry-prefixed (`entryN.key` / `entryN.value`) because the carried
# header repeats — a flat `key value` map would collapse the five gmail rows
# into one.

# A `key: value` line with a real value after the colon (Server:, Name:).
_skv_kv_re='^[[:space:]]*[A-Za-z][A-Za-z0-9_ .#-]*:[[:space:]]+[^[:space:]]'
# A bare `Header:` — alnum-led, ends in a colon with nothing after, no indent.
_skv_hdr_re='^[A-Za-z][A-Za-z0-9_ .,#()/-]*:[[:space:]]*$'

# Classify a raw line -> _SKV_KIND (K kv | H header | M member | -), and set
# _SKV_KEY / _SKV_VAL for K, _SKV_HDR for H, _SKV_MEM for M.
_skv_classify () {
    local l="$1"
    _SKV_KIND="-"
    [[ -z "${l//[[:space:]]/}" ]] && return
    if [[ "$l" =~ $_skv_kv_re ]]; then
        local s="${l#"${l%%[![:space:]]*}"}"       # lstrip
        _SKV_KEY="${s%%:*}"
        local v="${s#*:}"
        v="${v#"${v%%[![:space:]]*}"}"             # lstrip value
        v="${v%"${v##*[![:space:]]}"}"             # rstrip value
        _SKV_VAL="$v"
        _SKV_KIND="K"
        return
    fi
    if [[ "$l" =~ $_skv_hdr_re ]]; then
        local h="${l%:*}"
        h="${h%"${h##*[![:space:]]}"}"
        _SKV_HDR="$h"
        _SKV_KIND="H"
        return
    fi
    # A member: any other non-blank line. Tab column-alignment collapses to one
    # space so the carried value reads as one field.
    local m="$l"
    m="${m#"${m%%[![:space:]]*}"}"
    m="${m%"${m##*[![:space:]]}"}"
    m="${m//$'\t'/ }"
    while [[ "$m" == *"  "* ]]; do m="${m//  / }"; done
    _SKV_MEM="$m"
    _SKV_KIND="M"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line active="" nb=0 kv_before=0 sections=0 members_here=0 loose=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        _skv_classify "$line"
        case "$_SKV_KIND" in
            K) [[ $sections -eq 0 ]] && kv_before=$((kv_before + 1)) ;;
            H) active="H" ;;
            M)
                if [[ -z "$active" ]]; then
                    # A plain line before any header has no key to carry —
                    # this is not the section shape.
                    loose=$((loose + 1))
                else
                    members_here=$((members_here + 1))
                    if [[ "$active" == "H" ]]; then
                        sections=$((sections + 1)); active="S"
                    fi
                fi
                # A member holding its own `key: value` pair is kv territory,
                # not a carried plain line — reject rather than swallow it.
                [[ "$_SKV_MEM" == *": "* ]] && return 1
                # A carried member must have INTERNAL column structure — a tab
                # separating fields (nslookup's `domain <TAB> mail exchanger =
                # …`). The tab must be INTERNAL, not leading indentation: strip
                # the indent first, then require a tab in what remains, so
                # cgget's tab-INDENTED `\tusage_usec 8821004000` (indent + a
                # space-separated pair) does not qualify. This is the line that
                # separates this shape from the far commoner "trailing
                # `Description:` header over prose" (rpm -qi), "`Members:` over a
                # token-per-line list" (ipset), and "header-first event list"
                # (perf list): those carry free words, single tokens or
                # space-padding, never an embedded tab.
                local _skv_ls="${line#"${line%%[![:space:]]*}"}"
                [[ "$_skv_ls" == *$'\t'* ]] || return 1
                ;;
        esac
    done <<< "$text"
    # Need the defining shape: >=1 kv pair BEFORE any section (perf-list-style
    # header-first lists have none), then a bare header that carries >=2
    # tab-structured plain lines. Loose pre-header members / kv-pair members /
    # tab-less members already bailed above.
    [[ $loose -eq 0 && $kv_before -ge 1 && $sections -ge 1 && $members_here -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=70
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 header=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _skv_classify "$line"
        case "$_SKV_KIND" in
            K)
                entry=$((entry + 1))
                result+="entry${entry}.key ${_SKV_KEY}"$'\n'
                result+="entry${entry}.value ${_SKV_VAL}"$'\n'
                ;;
            H)
                header="$_SKV_HDR"
                ;;
            M)
                [[ -n "$header" ]] || continue
                entry=$((entry + 1))
                result+="entry${entry}.key ${header}"$'\n'
                result+="entry${entry}.value ${_SKV_MEM}"$'\n'
                ;;
        esac
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
