#!/bin/bash
## Name: boxed-table
## Description: an ASCII `+---+` box holding an aligned table, first box row = headers (likwid-topology) -> one row per box line — hint-routed
## Version: 1.0
## Priority: 48
## Sample: samples/boxed-table/basic.txt

# likwid-topology draws its cache table in an ASCII box, with a trailing
# level label inside each row and a `Socket N:` header above:
#
#   Socket 0:
#   +-------------------------------------+
#   | Core 0  Core 1  Core 2  Core 3      |
#   | 32 kB   32 kB   32 kB   32 kB   L1  |
#   | 25 MB shared                    L3  |
#   +-------------------------------------+
#
# The reviewer: "Strip out the decoration, and then parse as a table." The
# `+--+` rules and `|` borders drop; the first box row names the columns; each
# later row splits at 2+ space runs. When a row's field count differs from
# the header count, its LAST field is a row label (L1/L2/L3) and the rest fill
# the columns positionally — that keeps the spanning `25 MB shared` row and
# the labelled full rows both sane. A `Header:` line above the box carries
# down as `section`. Non-box lines are chrome and drop.
#
# HINT-ONLY: routes on the box rule via hints.tsv.

_bt_split () {
    local s="$1"
    _BT_FIELDS=()
    while [[ "$s" =~ ^(.*[^ ])\ \ +([^ ].*)$ ]]; do
        s="${BASH_REMATCH[1]}"
        _BT_FIELDS=("${BASH_REMATCH[2]}" "${_BT_FIELDS[@]}")
    done
    [[ -n "$s" ]] && _BT_FIELDS=("$s" "${_BT_FIELDS[@]}")
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 section=""
    local -a headers=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        # A +----+ rule opens/closes a box; a new box forgets old headers.
        if [[ "$s" =~ ^\+-+\+$ ]]; then
            headers=()
            continue
        fi
        if [[ "$s" == \|*\| ]]; then
            # Inside the box: strip the borders.
            s="${s#|}"; s="${s%|}"
            s="${s#"${s%%[![:space:]]*}"}"
            s="${s%"${s##*[![:space:]]}"}"
            [[ -z "$s" ]] && continue
            _bt_split "$s"
            if [[ ${#headers[@]} -eq 0 ]]; then
                headers=("${_BT_FIELDS[@]}")
                continue
            fi
            entry=$((entry + 1))
            [[ -n "$section" ]] && result+="entry${entry}.section ${section}"$'\n'
            local -a fields=("${_BT_FIELDS[@]}")
            local label=""
            if [[ ${#fields[@]} -ne ${#headers[@]} && ${#fields[@]} -gt 1 ]]; then
                label="${fields[${#fields[@]}-1]}"
                unset 'fields[${#fields[@]}-1]'
            fi
            local i
            for ((i = 0; i < ${#headers[@]} && i < ${#fields[@]}; i++)); do
                result+="entry${entry}.${headers[i]// /_} ${fields[i]}"$'\n'
            done
            [[ -n "$label" ]] && result+="entry${entry}.label ${label}"$'\n'
            continue
        fi
        # Outside a box: a bare `Header:` carries down as the section.
        if [[ "$s" == *: && "${s%:}" != *:* ]]; then
            section="${s%:}"
        fi
    done <<< "$text"
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
