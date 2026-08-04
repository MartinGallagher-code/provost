#!/bin/bash
## Name: describe-report
## Description: kubectl-describe style reports — aligned kv + continuations + `Section:` dashed tables -> section rows with kv carried
## Version: 1.0
## Priority: 21
## Sample: samples/describe-report/basic.txt

# `kubectl describe <kind>`'s house style:
#
#   Name:                   api-gateway
#   Labels:                 app=api-gateway
#                           tier=frontend
#   Conditions:
#     Type           Status  Reason
#     ----           ------  ------
#     Available      True    MinimumReplicasAvailable
#   Events:
#     Type    Reason   Age  From      Message
#     ----    ------   ---  ----      -------
#     Normal  Scaling  12m  deployer  Scaled up …
#
# Three shapes in one report: 2+-space-aligned top kv, deep-indented
# CONTINUATION lines belonging to the kv above (Labels' second value,
# Annotations' JSON), and `Section:` headers over an indented table whose
# `----` separator row gives the EXACT column extents. The old parse welded
# JSON fragments into key names and dropped whole events.
#
# One record per section-table row: `section` + the table's own header names
# as columns, values sliced at the dash-run positions (so `Warning
# FailedCreate` — a single space — still splits from its neighbors, and the
# free-text Message column keeps ALL its words). Top kv pairs emit as flat
# fields, which the melt repeats onto every row — wide, but nothing is lost.
# Continuations join their kv's value with `; `.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line kv=0 sections=0 in_section=0 expect=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" == [A-Za-z]* ]]; then
            in_section=0
            if [[ "$line" =~ ^[A-Za-z][A-Za-z0-9_\ .-]*:$ ]]; then
                in_section=1; expect="header"
            elif [[ "$line" =~ ^[A-Za-z][A-Za-z0-9_\ .-]*:[[:space:]]{2,}[^[:space:]] ]]; then
                kv=$((kv + 1))
            fi
            continue
        fi
        # Indented: a section's header/dashes/rows, or a kv continuation.
        if [[ $in_section -eq 1 ]]; then
            case "$expect" in
                header) expect="dashes" ;;
                dashes)
                    # the defining row: dash runs only
                    if [[ "$line" =~ ^[[:space:]]+-+([[:space:]]+-+)*[[:space:]]*$ ]]; then
                        sections=$((sections + 1))
                    fi
                    expect="" ;;
            esac
        fi
    done <<< "$text"
    # The full describe shape: several aligned kv pairs AND >=1 dashed table.
    [[ $kv -ge 3 && $sections -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    local kv_out="" cur_key="" cur_val=""
    local section="" state="" hdr_line=""
    local -a col_start=() col_name=()

    _dr_flush_kv () {
        if [[ -n "$cur_key" ]]; then
            kv_out+="${cur_key} ${cur_val}"$'\n'
        fi
        cur_key=""; cur_val=""
    }

    # Slice "$1" at the recorded column starts -> _DR_CELLS[] (last col = rest).
    # OVERFLOW-safe: a cell wider than its dash run (hpa's
    # `FailedGetResourceMetric` under `------`) straddles the next boundary —
    # when the characters on BOTH sides of a boundary are non-space, the
    # boundary walks right to the end of the straddling token so the token
    # stays whole in its own (left) column.
    _dr_slice () {
        # NOTE: split declarations — `local x="$1" y=${#x}` breaks under the
        # engine's `set -u` (y expands before x is assigned).
        local row="$1"
        local i n=${#col_start[@]}
        local rl=${#row}
        _DR_CELLS=()
        local s=${col_start[0]} b
        for ((i = 0; i < n; i++)); do
            if [[ $((i + 1)) -lt $n ]]; then
                b=${col_start[$((i + 1))]}
                [[ $b -lt $s ]] && b=$s
                # snap right past a straddling token
                while [[ $b -gt 0 && $b -lt $rl && "${row:$((b - 1)):1}" != " " && "${row:$b:1}" != " " ]]; do
                    b=$((b + 1))
                done
                local c="${row:$s:$((b - s))}"
                c="${c#"${c%%[![:space:]]*}"}"
                _DR_CELLS+=("${c%"${c##*[![:space:]]}"}")
                s=$b
            else
                local c="${row:$s}"
                c="${c#"${c%%[![:space:]]*}"}"
                _DR_CELLS+=("${c%"${c##*[![:space:]]}"}")
            fi
        done
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" == [A-Za-z]* ]]; then
            # top level: closes any open section
            state=""
            if [[ "$line" =~ ^([A-Za-z][A-Za-z0-9_\ .-]*):$ ]]; then
                _dr_flush_kv
                section="${BASH_REMATCH[1]// /_}"
                state="want_header"
            elif [[ "$line" =~ ^([A-Za-z][A-Za-z0-9_\ .-]*):[[:space:]]+(.*)$ ]]; then
                _dr_flush_kv
                cur_key="${BASH_REMATCH[1]// /_}"
                cur_val="${BASH_REMATCH[2]%"${BASH_REMATCH[2]##*[![:space:]]}"}"
            fi
            continue
        fi
        # Indented line.
        case "$state" in
            want_header)
                hdr_line="$line"; state="want_dashes" ;;
            want_dashes)
                if [[ "$line" =~ ^[[:space:]]+-+([[:space:]]+-+)*[[:space:]]*$ ]]; then
                    # Record column starts from the dash runs, names from the header.
                    col_start=(); col_name=()
                    local i=0 in_dash=0 ch
                    for ((i = 0; i < ${#line}; i++)); do
                        ch="${line:$i:1}"
                        if [[ "$ch" == "-" && $in_dash -eq 0 ]]; then
                            col_start+=("$i"); in_dash=1
                        elif [[ "$ch" != "-" ]]; then
                            in_dash=0
                        fi
                    done
                    _dr_slice "$hdr_line"
                    col_name=("${_DR_CELLS[@]}")
                    state="rows"
                else
                    # not a dashed table after all — treat both as continuations
                    local c1="$hdr_line" c2="$line"
                    c1="${c1#"${c1%%[![:space:]]*}"}"; c1="${c1%"${c1##*[![:space:]]}"}"
                    c2="${c2#"${c2%%[![:space:]]*}"}"; c2="${c2%"${c2##*[![:space:]]}"}"
                    [[ -n "$cur_key" ]] && cur_val+="; ${c1}; ${c2}"
                    state=""
                fi
                ;;
            rows)
                _dr_slice "$line"
                entry=$((entry + 1))
                result+="entry${entry}.section ${section}"$'\n'
                local i
                for ((i = 0; i < ${#col_name[@]}; i++)); do
                    local nm="${col_name[$i]// /_}" cv="${_DR_CELLS[$i]}"
                    [[ -n "$nm" && -n "$cv" ]] || continue
                    result+="entry${entry}.${nm} ${cv}"$'\n'
                done
                ;;
            *)
                # continuation of the open kv
                local c="$line"
                c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
                [[ -n "$cur_key" && -n "$c" ]] && cur_val+="; ${c}"
                ;;
        esac
    done <<< "$text"
    _dr_flush_kv
    result+="$kv_out"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
