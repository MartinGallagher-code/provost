#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: headline-kv-blocks
## Description: blank-separated blocks opening with a `name  range` headline over `Key: value` lines (npm audit) -> name + headline/kv/detail columns
## Version: 1.0
## Priority: 36
## Sample: samples/headline-kv-blocks/basic.txt

# `npm audit`'s report form — each advisory is a blank-separated block whose
# FIRST line is a headline (the package and its vulnerable range, 2+-space
# aligned), followed by `Key: value` lines and free lines:
#
#   # npm audit report
#
#   lodash  <4.17.21
#   Severity: high
#   Prototype Pollution - https://github.com/advisories/GHSA-xxxx
#   fix available via `npm audit fix`
#
#   3 vulnerabilities (1 moderate, 2 high)
#
# block-records kept ONLY the `Severity: high` line — the reviewer's "missed
# columns". Here each qualifying block is one record:
#   * headline: first field (before the 2+-space run) -> `name`; remaining
#     headline fields -> positional A, B, … columns;
#   * `Key: value` lines -> their own named columns;
#   * a free line holding ` - ` -> its two sides as further positional
#     columns (title/advisory-url pairs);
#   * other free lines -> `detail`, `; `-joined.
# A leading title block (`# npm audit report`) and a trailing summary block
# (the totals line) are tolerated as chrome; any OTHER non-qualifying block
# rejects detection.

# Does "$1" (a whole block, newline-separated) qualify? First line must be a
# headline: no `: `, contains a 2+-space run, >=2 fields; and >=1 later line
# must be `Key: value`.
_hkb_qualifies () {
    local block="$1" first="" line n=0 kv=0
    _fr_lines "$block"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        n=$((n + 1))
        if [[ $n -eq 1 ]]; then
            first="$line"
            [[ "$first" == *": "* ]] && return 1
            [[ "$first" =~ [^[:space:]]\ \ +[^[:space:]] ]] || return 1
            [[ "$first" == [A-Za-z@]* ]] || return 1
        else
            [[ "$line" =~ ^[A-Za-z][A-Za-z0-9_\ -]*:\ [^[:space:]] ]] && kv=$((kv + 1))
        fi
    done
    [[ $n -ge 2 && $kv -ge 1 ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Split into blank-separated blocks.
    local line block="" q=0 nq=0 order=""
    # (a block's lines collect in an array and are joined once when it closes
    # — `block+=` per line re-copied the growing block: quadratic)
    local -a _hkb_cur=()
    _hkb_blocks=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "${line}" != *[![:space:]]* ]]; then
            if [[ ${#_hkb_cur[@]} -gt 0 ]]; then
                printf -v block '%s\n' "${_hkb_cur[@]}"
                _hkb_blocks+=("${block%$'\n'}")
            fi
            _hkb_cur=(); block=""
            continue
        fi
        _hkb_cur+=("$line")
    done
    if [[ ${#_hkb_cur[@]} -gt 0 ]]; then
        printf -v block '%s\n' "${_hkb_cur[@]}"
        _hkb_blocks+=("${block%$'\n'}")
    fi

    local b i=0 total=${#_hkb_blocks[@]}
    [[ $total -ge 2 ]] || return 1
    for b in "${_hkb_blocks[@]}"; do
        i=$((i + 1))
        if _hkb_qualifies "$b"; then
            q=$((q + 1)); order+="Q"
        else
            # tolerated only as the very first (title) or very last (summary)
            [[ $i -eq 1 || $i -eq $total ]] || return 1
            order+="N"
        fi
    done
    [[ $q -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=74
    return 0
}

strategy_extract () {
    local text="$1"
    # Re-split blocks (detect and extract run in separate passes).
    local line block="" result="" entry=0
    local -a blocks=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "${line}" != *[![:space:]]* ]]; then
            [[ -n "$block" ]] && blocks+=("${block%$'\n'}")
            block=""
            continue
        fi
        block+="$line"$'\n'
    done
    line=""
    [[ -n "$block" ]] && blocks+=("${block%$'\n'}")

    local b
    for b in "${blocks[@]}"; do
        _hkb_qualifies "$b" || continue
        entry=$((entry + 1))
        local n=0 pos=0 detail="" col
        while IFS= read -r line; do
            [[ "${line}" != *[![:space:]]* ]] && continue
            n=$((n + 1))
            if [[ $n -eq 1 ]]; then
                # headline: name + positional fields, split on 2+-space runs
                local rest="$line"
                local name="${rest%%  *}"
                result+="entry${entry}.name ${name}"$'\n'
                rest="${rest#*  }"
                while :; do
                    rest="${rest#"${rest%%[![:space:]]*}"}"
                    [[ -n "$rest" ]] || break
                    local f
                    if [[ "$rest" == *"  "* ]]; then
                        f="${rest%%  *}"; rest="${rest#*  }"
                    else
                        f="$rest"; rest=""
                    fi
                    col=$(printf "\\$(printf '%03o' $((65 + pos)))")
                    pos=$((pos + 1))
                    result+="entry${entry}.${col} ${f}"$'\n'
                done
                continue
            fi
            if [[ "$line" =~ ^([A-Za-z][A-Za-z0-9_\ -]*):\ +(.+)$ ]]; then
                local k="${BASH_REMATCH[1]}" v="${BASH_REMATCH[2]}"
                k="${k// /_}"
                v="${v%"${v##*[![:space:]]}"}"
                result+="entry${entry}.${k} ${v}"$'\n'
                continue
            fi
            if [[ "$line" == *" - "* ]]; then
                # `Title - URL` free line -> two positional columns
                local lhs="${line%% - *}" rhs="${line#* - }"
                col=$(printf "\\$(printf '%03o' $((65 + pos)))")
                pos=$((pos + 1))
                result+="entry${entry}.${col} ${lhs}"$'\n'
                col=$(printf "\\$(printf '%03o' $((65 + pos)))")
                pos=$((pos + 1))
                result+="entry${entry}.${col} ${rhs}"$'\n'
                continue
            fi
            detail+="${detail:+; }${line}"
        done <<< "$b"
        [[ -n "$detail" ]] && result+="entry${entry}.detail ${detail}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
