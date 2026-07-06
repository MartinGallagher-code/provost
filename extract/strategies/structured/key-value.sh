#!/bin/bash
## Name: key-value
## Description: Generic aligned "Label:   value" listings (lscpu, hwinfo, tool --status output) as a two-column key/value table
## Version: 1.0
## Priority: 11
## Technique: yes
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

    while IFS= read -r line; do
        t="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
        [[ -z "$t" ]] && continue

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

    local result="" i
    for ((i=1; i<=n; i++)); do
        result+="entry${i}.key ${K[$i]}"$'\n'
        [[ -n "${V[$i]}" ]] && result+="entry${i}.value ${V[$i]}"$'\n'
    done
    (( n > 0 )) && result+="total_entries ${n}"$'\n'

    echo "$result"
}
