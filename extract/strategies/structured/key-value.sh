#!/bin/bash
## Name: key-value
## Description: Generic aligned "Label:   value" listings (lscpu, hwinfo, tool --status output) as a two-column key/value table
## Version: 1.0
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
    while IFS= read -r line; do
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
        if [[ "$after" == "  "* || -z "${after//[[:space:]]/}" ]]; then
            aligned=$((aligned + 1))
        fi
        [[ "$key" == *" "* ]] && spacey=$((spacey + 1))
    done <<< "$text"

    [[ $listmark -gt 0 ]] && return 1
    [[ $kv -lt 5 ]] && return 1
    # Most non-empty lines must be key:value (wrapped continuations are the rest).
    (( kv * 2 < nonempty )) && return 1
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
    local line t key value cont

    # `_await_val` is set after a BARE label line (`webpage:` with nothing
    # after the colon). The reviewer's rule: the value then sits on the line(s)
    # below, so the next non-blank line is that value VERBATIM — its own colons
    # are data, not a new key (`https://busybox.net/`, `so:libc.musl…`,
    # `cmd:busybox=1.36.1-r5`). Without this the URL's `https:` became a spurious
    # key and the real value was lost (apk info -a).
    # A line is STRUCTURAL kv when a colon is followed by an aligned value
    # (2+ spaces) or the line is a bare label (colon at end). A URL
    # (`https://…`), a `so:lib…` / `cmd:pkg=…` token — colon NOT followed by a
    # space — is NOT structural, so it folds as a value below its label.
    _kv_structural () {
        local x="$1"
        [[ "$x" =~ ^[A-Za-z][^:]*:$ ]] && return 0            # bare label
        [[ "$x" =~ ^[A-Za-z][^:]*:[[:space:]][[:space:]] ]] && return 0
        return 1
    }
    local _await_val=0
    while IFS= read -r line; do
        t="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
        [[ -z "$t" ]] && { _await_val=0; continue; }   # blank ends a value block

        # A below-the-line value: fold it — UNLESS it is itself a structural
        # kv line, which means the bare label above it was a SECTION HEADER
        # (aide-check's `Summary:` over `Total …:  184203`), not a label
        # awaiting a value.
        if [[ $_await_val -eq 1 ]] && ! _kv_structural "$t"; then
            cont="${t%"${t##*[![:space:]]}"}"
            if [[ -n "${V[$n]}" ]]; then V[$n]="${V[$n]} ${cont}"; else V[$n]="$cont"; fi
            continue
        fi
        _await_val=0

        if [[ "$t" == *:* ]]; then
            key="${t%%:*}"
            value="${t#*:}"
            key="${key%"${key##*[![:space:]]}"}"                 # trim key trailing ws
            value="${value#"${value%%[![:space:]]*}"}"           # trim value leading ws
            value="${value%"${value##*[![:space:]]}"}"           # trim value trailing ws
            [[ -z "$key" ]] && continue
            n=$((n + 1))
            K[$n]="$key"
            V[$n]="$value"
            # a bare label opens a below-the-line value block
            [[ -z "$value" ]] && _await_val=1
        elif (( n > 0 )); then
            # Wrapped continuation line — fold into the previous value.
            cont="${t%"${t##*[![:space:]]}"}"
            if [[ -n "${V[$n]}" ]]; then
                V[$n]="${V[$n]} ${cont}"
            else
                V[$n]="$cont"
            fi
        fi
    done <<< "$text"

    # Drop bare SECTION-HEADER labels — an empty-value key immediately
    # followed by another key is a heading ("Summary:" over the totals), not
    # a field; the reviewer flagged it as a spurious row. A trailing empty-
    # value key (a real field that happens to be blank) is kept.
    local result="" i entry=0
    for ((i=1; i<=n; i++)); do
        if [[ -z "${V[$i]}" && $i -lt $n ]]; then continue; fi
        entry=$((entry + 1))
        result+="entry${entry}.key ${K[$i]}"$'\n'
        [[ -n "${V[$i]}" ]] && result+="entry${entry}.value ${V[$i]}"$'\n'
    done
    (( entry > 0 )) && result+="total_entries ${entry}"$'\n'

    echo "$result"
}
