#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: key-value
## Description: Generic aligned "Label:   value" listings (lscpu, hwinfo, tool --status output) as a two-column key/value table
## Version: 1.1
## Priority: 11
## Sample: samples/key-value/basic.txt

# Many tools print a flat/indented list of "Label:   value" pairs with the
# value column whitespace-aligned (lscpu, hwinfo, `systemctl show`-ish, various
# `--status`/`--info` dumps). Rather than a bespoke strategy per command, this
# captures ANY such listing as indexed key/value row groups
# (entry<N>.key / entry<N>.value) so the capture tidy melt renders a clean
# two-column table — one row per property — instead of one unreadable wide
# record. Wrapped continuation lines (no colon) fold into the previous value.
#
# Detection deliberately targets *aligned* human-readable output (2+ spaces
# after the colon, and/or multi-word labels) and rejects YAML list/documents,
# so it does not steal compact `key: value` YAML/config or JSON.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    _is_json "$text" && return 1

    local nonempty=0 kv=0 aligned=0 spacey=0 listmark=0
    local line t key after
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        t="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
        [[ -z "$t" ]] && continue
        nonempty=$((nonempty + 1))

        # YAML list items / document markers disqualify the whole input.
        case "$t" in
            '- '*|'-'|'---'*|'...'*) listmark=$((listmark + 1)); continue ;;
        esac

        [[ "$t" == *:* ]] || continue
        key="${t%%:*}"
        [[ -z "$key" ]] && continue
        kv=$((kv + 1))

        after="${t#*:}"
        # Aligned value column (2+ spaces after the colon) or a bare section
        # header (nothing after the colon) — the hallmark of tool display output.
        if [[ "$after" == "  "* || "${after}" != *[![:space:]]* ]]; then
            aligned=$((aligned + 1))
        fi
        [[ "$key" == *" "* ]] && spacey=$((spacey + 1))
    done

    [[ $listmark -gt 0 ]] && return 1
    [[ $kv -lt 5 ]] && return 1
    # Most non-empty lines must be key:value (wrapped continuations are the rest).
    (( kv * 100 < nonempty * (50 - ${_FR_SLACK:-0}) )) && return 1
    # Require BOTH an aligned value column AND several multi-word labels — the
    # signature of human-readable tool dumps (lscpu, hwinfo, `systemctl show`).
    # This deliberately leaves single-word-key formats (/proc/meminfo) and
    # compact YAML/config to their own strategies.
    if (( aligned >= 3 && spacey >= 3 )); then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local -a K V
    local n=0
    local line t key value cont ind

    # A line is a KEY line when it has a STRUCTURAL colon — a colon followed
    # by whitespace or the end of the line — and the text before the first
    # such colon reads as a label: past any tree glyphs (`|- `, `` `- ``) it
    # opens with a letter, a digit, `.`, `/`, `[` or `%` (`.NET SDK:`,
    # `/dev/sda:`, `%Cpu(s):`,
    # `[build] use-vbo=false:`, `95th percentile:`, objdump's `1c:` offsets),
    # is at most 60
    # characters and 8 words, holds at most two colons of its own and is not
    # a hex string (`ab:cd:ef:` wrapping a key dump), and holds no `://`.
    # The key is everything
    # before that colon, so a label that itself holds a colon stays whole
    # (ffmpeg's `Stream #0:1[0x2](und): Audio: aac …` → key `Stream
    # #0:1[0x2](und)`, value `Audio: aac …`; it used to split at `#0:`). A
    # URL (`https://…`), a `so:libc…` / `cmd:pkg=…` token or a `key=v
    # t=0:01` progress line is TEXT. Sets _KV_K / _KV_V.
    _kv_keyline () {
        local s="$1" pre rest
        while [[ "$s" == [\|\`+\\-]* ]]; do s="${s#?}"; s="${s#"${s%%[![:space:]]*}"}"; done
        [[ "$s" =~ ^[A-Za-z0-9./[%] ]] || return 1
        pre=""; rest="$s"
        while [[ "$rest" == *:* ]]; do
            pre+="${rest%%:*}"; rest="${rest#*:}"
            if [[ -z "$rest" || "$rest" == [[:space:]]* ]]; then
                pre="${pre%"${pre##*[![:space:]]}"}"
                [[ ${#pre} -le 60 && "$pre" != *"://"* ]] || return 1
                [[ "$pre" == *:*:*:* || "$pre" =~ ^([0-9A-Fa-f]{2}:)+[0-9A-Fa-f]{2}$ ]] && return 1
                # (dot leaders — `Description . . . . :` — are not words)
                local -a _w; read -ra _w <<< "${pre//./ }"
                [[ ${#_w[@]} -le 8 ]] || return 1
                _KV_K="$pre"
                rest="${rest#"${rest%%[![:space:]]*}"}"
                _KV_V="${rest%"${rest##*[![:space:]]}"}"
                return 0
            fi
            pre+=":"
        done
        return 1
    }
    # indent width of a line (a tab counts 8)
    _kv_ind () {
        local l="${1%%[![:space:]]*}"
        l="${l//$'\t'/        }"
        _KV_IND=${#l}
    }

    # `_await_val` is set after a BARE label line (`webpage:` with nothing
    # after the colon). The value then sits on the line(s) below, so the next
    # non-blank lines are that value VERBATIM — their own colons are data,
    # not a new key (`https://busybox.net/`, `so:libc.musl…`,
    # `cmd:busybox=1.36.1-r5`; apk info -a). Lines at the label's own indent
    # fold into one value, as before. Lines DEEPER than the label are its
    # ITEMS: two or more become one row each, the label repeated as the key
    # (ffmpeg's `Stream mapping:` over its stream lines, a `Registry
    # Mirrors:` list) instead of one cell holding the whole list; a single
    # one is still its value. A key line below a bare label means the label
    # was a SECTION HEADER (aide-check's `Summary:` over `Total …:  184203`).
    # Outside a value block, a TEXT line deeper than the entry's key line (or
    # below a key whose value is still empty) is a wrapped continuation and
    # folds into its value; a text line at or left of the key's indent is not
    # a continuation of it (ffmpeg's `Press [q] to stop` after an indented
    # list): it becomes its own row.
    local _await_val=0 _lab_ind=0 _key_ind=0 _items=() _it _text_row=0
    _kv_flush_items () {
        # (a WRAPPED value is folded, not itemised: a piece before the last
        # ends in `,` / `:` / `;` — a comma list, a hex dump — or runs
        # over 60 bytes)
        local _wrap=0
        for _it in "${_items[@]:0:${#_items[@]}-1}"; do
            [[ "$_it" == *[,:\;] || ${#_it} -gt 60 ]] && { _wrap=1; break; }
        done
        if [[ $_wrap -eq 1 ]]; then
            local _jv="${_items[*]}"
            if [[ -n "${V[$n]}" ]]; then V[$n]="${V[$n]} ${_jv}"; else V[$n]="$_jv"; fi
            _items=(); return
        fi
        if [[ ${#_items[@]} -ge 2 ]]; then
            local _fk="${K[$n]}" _first=1
            [[ -z "${V[$n]}" ]] && { V[$n]="${_items[0]}"; _first=0; }
            for _it in "${_items[@]:$((1 - _first))}"; do
                n=$((n + 1)); K[$n]="$_fk"; V[$n]="$_it"
            done
        elif [[ ${#_items[@]} -eq 1 ]]; then
            if [[ -n "${V[$n]}" ]]; then V[$n]="${V[$n]} ${_items[0]}"; else V[$n]="${_items[0]}"; fi
        fi
        _items=()
    }
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        t="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
        if [[ -z "$t" ]]; then                  # blank ends a value block
            [[ $_await_val -eq 1 ]] && _kv_flush_items
            _await_val=0; continue
        fi
        _kv_ind "$line"; ind=$_KV_IND
        cont="${t%"${t##*[![:space:]]}"}"
        # a bare rule (`====`, `-----`) is chrome
        [[ "$cont" =~ ^[-=_*~+]{3,}$ ]] && continue
        # (a bare-number key right under a bare label, deeper — LUKS's
        # `Keyslots:` / `  0: luks2` — is one of its items, as before)
        if [[ $_await_val -eq 1 && $ind -gt $_lab_ind && "$t" =~ ^[0-9]+:[[:space:]] ]]; then
            _items+=("$cont"); continue
        fi
        if _kv_keyline "$t"; then
            [[ $_await_val -eq 1 ]] && _kv_flush_items
            _await_val=0
            n=$((n + 1)); K[$n]="$_KV_K"; V[$n]="$_KV_V"; _key_ind=$ind; _text_row=0
            # a bare label opens a below-the-line value block
            [[ -z "$_KV_V" ]] && { _await_val=1; _lab_ind=$ind; }
            continue
        fi
        if [[ $_await_val -eq 1 ]]; then
            if [[ $ind -gt $_lab_ind ]]; then
                _items+=("$cont")
            elif [[ ${#_items[@]} -eq 0 ]]; then
                if [[ -n "${V[$n]}" ]]; then V[$n]="${V[$n]} ${cont}"; else V[$n]="$cont"; fi
            else
                _kv_flush_items; _await_val=0
                n=$((n + 1)); K[$n]="$cont"; V[$n]=""; _key_ind=$ind; _text_row=1
            fi
            continue
        fi
        # A text line before any key is a banner: dropped, as always (a
        # table-shaped listing counts its rows), unless it carries a `: ` —
        # then it is kept, split there (top's `top - 10:14:52 up …, load
        # average: 0.84, …`).
        if (( n == 0 )); then
            [[ "$cont" == *": "* ]] || continue
            n=1; K[$n]="${cont%%: *}"; V[$n]="${cont#*: }"; _key_ind=$ind; _text_row=0
            continue
        fi
        # (a bare label's value may also sit below it across a blank line:
        # hdparm's `/dev/sda:` / blank / `ATA device, with …`)
        # (a deeper line holding a column gap is a table row, not wrapped
        # text: top's process rows under `MiB Swap:` are rows of their own)
        if [[ "$cont" != *[![:space:]]"  "*[![:space:]]* \
              && ( $ind -gt $_key_ind || ( -z "${V[$n]}" && $_text_row -eq 0 ) ) ]]; then
            # Wrapped continuation line — fold into the previous value.
            if [[ -n "${V[$n]}" ]]; then V[$n]="${V[$n]} ${cont}"; else V[$n]="$cont"; fi
        else
            n=$((n + 1)); K[$n]="$cont"; V[$n]=""; _key_ind=$ind; _text_row=1
        fi
    done
    [[ $_await_val -eq 1 ]] && _kv_flush_items

    # NOTE: bare section-header labels (aide-check's `Summary:`, lscpu's
    # `Caches (sum of all):`) are still emitted as empty-value rows. Dropping
    # them blindly loses GROUP context where the "header" actually
    # disambiguates repeated keys (sensors' `Core 0:` / `Core 1:` over the
    # same temp keys, docker's `Client:` / `Server:` over `Version`) — that
    # is the kv-under-group shape, deferred to a dedicated pivot round rather
    # than a blunt drop here.
    local result="" i
    for ((i=1; i<=n; i++)); do
        result+="entry${i}.key ${K[$i]}"$'\n'
        [[ -n "${V[$i]}" ]] && result+="entry${i}.value ${V[$i]}"$'\n'
    done
    (( n > 0 )) && result+="total_entries ${n}"$'\n'

    echo "$result"
}
