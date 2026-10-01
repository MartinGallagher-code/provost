#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: doe-info
## Description: Extract the design matrix from `doe info` / `doe generate --dry-run` output (doehelper), one row per experiment run
## Version: 1.0
## Priority: 22
## Sample: samples/doe-info/basic.txt

# `doe info` prints a `Key : value` plan header, a blank line, the design
# matrix (uniform-width ljust columns over a `---` rule), then an optional
# `Design Evaluation Metrics:` block. The matrix is the data; the header and
# metrics ride along as constant columns.
#
# Regexes live in variables so the literal brackets/parens in the header
# values (`yield [maximize] (%)`) never reach the [[ =~ ]] parser.
_doei_re_hdr='^(Plan|Desc|Operation|Factors|Base runs|Blocks|Total runs|Responses|Fixed)[[:space:]]*:[[:space:]]*(.*)$'
_doei_re_rule='^-+$'
_doei_re_metric='^[[:space:]]+([A-Za-z]-efficiency):[[:space:]]*(.+)$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == "Plan      :"* || "$text" == *$'\nPlan      :'* ]] || return 1
    [[ "$text" == *$'\nOperation :'* ]] || return 1
    [[ "$text" == *$'\nTotal runs:'* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    _STRATEGY_CONFIDENCE_REASON="doe info plan header (Plan/Operation/Total runs) present"
    return 0
}

_doei_trim () {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# Field-name-safe key: lowercase, non-alnum -> underscore.
_doei_key () {
    local s="$1" out="" c i
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:$i:1}"
        case "$c" in
            [A-Za-z0-9]) out+="$c" ;;
            *)           out+="_" ;;
        esac
    done
    printf '%s' "$(echo "$out" | tr '[:upper:]' '[:lower:]')"
}

strategy_extract () {
    local text="$1"
    local result="" line
    local -a cols=()
    local ncols=0 colw=0 n=0 in_matrix=0 seen_rule=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Plan header — `Key : value` before the matrix.
        if [[ $in_matrix -eq 0 && "$line" =~ $_doei_re_hdr ]]; then
            local k v
            k="$(_doei_key "$(_doei_trim "${BASH_REMATCH[1]}")")"
            v="$(_doei_trim "${BASH_REMATCH[2]}")"
            [[ -n "$v" ]] && result+="${k} ${v}"$'\n'
            continue
        fi
        # Design Evaluation Metrics block (after the matrix).
        if [[ "$line" =~ $_doei_re_metric ]]; then
            local mk mv
            mk="$(_doei_key "${BASH_REMATCH[1]}")"
            mv="$(_doei_trim "${BASH_REMATCH[2]}")"
            result+="${mk} ${mv}"$'\n'
            in_matrix=0
            continue
        fi
        # The matrix header names the columns; the rule line under it confirms.
        if [[ $in_matrix -eq 0 && "$line" == run_id* ]]; then
            { _fr_tok "$line"; cols=("${_FR_TOK[@]}"); }
            ncols=${#cols[@]}
            # Uniform ljust width: the header's own span / column count.
            local hdr_len=${#line}
            (( ncols > 0 )) && colw=$(( hdr_len / ncols ))
            in_matrix=1
            seen_rule=0
            continue
        fi
        if [[ $in_matrix -eq 1 && $seen_rule -eq 0 && "$line" =~ $_doei_re_rule ]]; then
            seen_rule=1
            continue
        fi
        if [[ $in_matrix -eq 1 ]]; then
            # Blank line ends the matrix.
            [[ "${line}" != *[![:space:]]* ]] && { in_matrix=0; continue; }
            # Slice by the uniform column width so a value containing a space
            # stays in its own column.
            local -a vals=()
            local i off cell
            for ((i = 0; i < ncols; i++)); do
                off=$(( i * colw ))
                if (( i == ncols - 1 )); then
                    cell="${line:$off}"
                else
                    cell="${line:$off:$colw}"
                fi
                vals+=("$(_doei_trim "$cell")")
            done
            # A real data row has a non-empty first cell.
            [[ -z "${vals[0]}" ]] && continue
            n=$((n + 1))
            local p="entry${n}."
            for ((i = 0; i < ncols; i++)); do
                result+="${p}$(_doei_key "${cols[$i]}") ${vals[$i]}"$'\n'
            done
            continue
        fi
    done

    result+="total_entries ${n}"$'\n'
    printf '%s' "$result"
}
