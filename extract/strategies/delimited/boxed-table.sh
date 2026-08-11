#!/bin/bash
## Name: boxed-table
## Description: an ASCII `+---+` box holding an aligned table, first box row = headers (likwid-topology) -> one row per box line — hint-routed
## Version: 1.1
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
# v1.1 also handles the OTHER kind of ASCII box, the one the AWS CLI's `table`
# output draws, where interior `|` characters are real column delimiters:
#
#   --------------------------------------------------
#   |                  ListBuckets                   |
#   +----------------------------+-------------------+
#   |            Name            |   CreationDate    |
#   +----------------------------+-------------------+
#   |  acme-prod-assets          |  2024-03-11T08:14Z |
#
# The reviewer, across eleven of these at once: "The pipes are delimiters, and
# should not appear in the output", and "Dataset 1 has the headers for what is
# now dataset 2". Splitting on 2+ spaces cannot read this — a value with a
# space in it would break apart, and the pipes came through as their own cells.
# When a box row has interior pipes, they are the split. A row that yields a
# SINGLE cell is the table's caption (`ListBuckets`), kept in a `table` column
# so the name of the call that produced the rows is not lost; the first
# multi-cell row is the header. 52 corpus inputs are this shape.
#
# HINT-ONLY: routes on the box rule via hints.tsv.

# Split a box row into cells. Interior pipes win when present, because they
# are explicit; otherwise fall back to runs of 2+ spaces.
_bt_split () {
    local s="$1"
    _BT_FIELDS=()
    if [[ "$s" == *"|"* ]]; then
        local IFS='|' cellv
        local -a raw=()
        read -ra raw <<< "$s"
        for cellv in "${raw[@]}"; do
            cellv="${cellv#"${cellv%%[![:space:]]*}"}"
            cellv="${cellv%"${cellv##*[![:space:]]}"}"
            _BT_FIELDS+=("$cellv")
        done
        return 0
    fi
    while [[ "$s" =~ ^(.*[^ ])\ \ +([^ ].*)$ ]]; do
        s="${BASH_REMATCH[1]}"
        _BT_FIELDS=("${BASH_REMATCH[2]}" "${_BT_FIELDS[@]}")
    done
    [[ -n "$s" ]] && _BT_FIELDS=("$s" "${_BT_FIELDS[@]}")
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 section="" caption=""
    local -a headers=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        # A rule opens/closes a box. `+---+---+` for a single-column box,
        # `+---+---+---+` between columns, and a bare `-----` above an AWS
        # caption — none of them are data, and none should reset the header
        # once one has been read (the AWS shape rules between EVERY row).
        if [[ "$s" =~ ^[-+]+$ ]]; then
            [[ ${#headers[@]} -eq 0 ]] && headers=()
            continue
        fi
        if [[ "$s" == \|*\| ]]; then
            # Inside the box: strip the borders.
            s="${s#|}"; s="${s%|}"
            s="${s#"${s%%[![:space:]]*}"}"
            s="${s%"${s##*[![:space:]]}"}"
            [[ -z "$s" ]] && continue
            _bt_split "$s"
            # A single-cell row inside the box is the table's caption, not a
            # header and not a row: `| ListBuckets |` names the whole table.
            if [[ ${#_BT_FIELDS[@]} -eq 1 && ${#headers[@]} -eq 0 && -z "$caption" ]]; then
                caption="${_BT_FIELDS[0]}"
                continue
            fi
            if [[ ${#headers[@]} -eq 0 ]]; then
                headers=("${_BT_FIELDS[@]}")
                continue
            fi
            entry=$((entry + 1))
            [[ -n "$caption" ]] && result+="entry${entry}.table ${caption}"$'\n'
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
    _STRATEGY_CONFIDENCE=0
    local text="$1"
    # The SPACE-split box (likwid) stays hint-only: nothing about it is
    # distinctive enough to claim on sight. The PIPE box is another matter —
    # every line of the table is fenced `|…|`, the frame is drawn with `+---+`
    # rules, and at least one row carries an interior pipe. Nothing else in the
    # corpus looks like that, and a psql-style table (` a | b `, no fence) does
    # not match, which is the distinction that keeps 40-odd working parses out
    # of here.
    local line npipe=0 nrule=0 ninner=0
    while IFS= read -r line; do
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        case "$s" in
            '|'*'|')
                npipe=$((npipe + 1))
                local body="${s#|}"; body="${body%|}"
                [[ "$body" == *"|"* ]] && ninner=$((ninner + 1))
                ;;
        esac
        if [[ "$s" =~ ^[-+]{4,}$ ]]; then nrule=$((nrule + 1)); fi
    done <<< "$text"
    [[ $npipe -ge 3 && $nrule -ge 2 && $ninner -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=82
    return 0
}
