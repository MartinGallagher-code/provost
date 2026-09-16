#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: doe-optimize
## Description: Extract RSM coefficients and factor importance from `doe optimize` output (doehelper)
## Version: 1.0
## Priority: 22
## Sample: samples/doe-optimize/basic.txt

# `doe optimize` prints one `=== Optimization: <response> ===` block per
# response, each carrying two row-shaped datasets among the prose:
#
#   RSM Model (linear, R² = 0.9615, Adj R² = 0.9471):
#     Coefficients:
#       intercept                      +72.4500
#       temperature                    +7.5783
#
#   Factor importance:
#     1. pressure  (effect: 4.4, contribution: 67.7%)
#
# Both become rows, discriminated by a `section` column (`coefficient` /
# `importance`) and keyed by `response` — the same shape `doe-analyze` uses
# for its Main Effects / ANOVA mix. Generic `block-records` was turning each
# coefficient into its own COLUMN of a single row instead.
#
# The narrative blocks (Best observed run, Curvature analysis, Predicted /
# Surface optimum, Model quality) are deliberately not parsed — they are
# prose and per-factor settings, not a table.
_doeo_re_hdr='^===[[:space:]]*Optimization:[[:space:]]*(.*[^[:space:]])[[:space:]]*===[[:space:]]*$'
_doeo_re_dir='^Direction:[[:space:]]*([^[:space:]]+)'
# One pattern for the whole `RSM Model (linear, R² = 0.9615, Adj R² = 0.9471):`
# line: model name, then the two `= <number>` values in order. Matching the
# numbers positionally rather than by their labels keeps this independent of
# the multi-byte `²`, which a single `.` cannot match reliably.
_doeo_re_model='^[[:space:]]*RSM Model[[:space:]]*\(([a-z]+),'
_doeo_re_fits='=[[:space:]]*([0-9.eE+-]+),.*=[[:space:]]*([0-9.eE+-]+)[[:space:]]*\)'
_doeo_re_coef='^[[:space:]]+([^[:space:]]+)[[:space:]]+([+-][0-9.eE+-]+)[[:space:]]*$'
_doeo_re_imp='^[[:space:]]+([0-9]+)\.[[:space:]]+([^[:space:]]+)[[:space:]]+\(effect:[[:space:]]*([0-9.eE+-]+),[[:space:]]*contribution:[[:space:]]*([0-9.eE+-]+)%\)'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == "=== Optimization: "* || "$text" == *$'\n=== Optimization: '* ]] || return 1
    [[ "$text" == *"RSM Model"* || "$text" == *"Factor importance:"* ]] || return 1
    _STRATEGY_CONFIDENCE=88
    _STRATEGY_CONFIDENCE_REASON="doe optimize block (=== Optimization: ... ===) with RSM/importance data"
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0
    local response="" model="" in_coef=0 in_imp=0
    local -a responses=()

    while IFS= read -r line; do
        if [[ "$line" =~ $_doeo_re_hdr ]]; then
            response="${BASH_REMATCH[1]}"
            responses+=("$response")
            model=""; in_coef=0; in_imp=0
            continue
        fi
        if [[ "$line" =~ $_doeo_re_dir ]]; then
            [[ -n "$response" ]] && result+="direction_${response} ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        # `RSM Model (linear, ...)` names the model the next Coefficients
        # block belongs to, and carries that model's fit statistics.
        if [[ "$line" =~ $_doeo_re_model ]]; then
            model="${BASH_REMATCH[1]}"
            in_coef=0; in_imp=0
            if [[ "$line" =~ $_doeo_re_fits ]]; then
                result+="r_squared_${response}_${model} ${BASH_REMATCH[1]}"$'\n'
                result+="adj_r_squared_${response}_${model} ${BASH_REMATCH[2]}"$'\n'
            fi
            continue
        fi
        case "$line" in
            *"Coefficients:"*)      in_coef=1; in_imp=0; continue ;;
            "Factor importance:"*)  in_imp=1;  in_coef=0; continue ;;
            # Any other indented sub-heading ends both blocks.
            *"Curvature analysis:"*|*"Notable interactions:"*|*"Predicted optimum"*|*"Surface optimum"*|*"Model quality:"*)
                in_coef=0; in_imp=0; continue ;;
        esac
        if [[ $in_coef -eq 1 ]]; then
            [[ -z "${line//[[:space:]]/}" ]] && { in_coef=0; continue; }
            if [[ "$line" =~ $_doeo_re_coef ]]; then
                n=$((n + 1))
                local p="entry${n}."
                result+="${p}section coefficient"$'\n'
                result+="${p}response ${response}"$'\n'
                result+="${p}model ${model}"$'\n'
                result+="${p}term ${BASH_REMATCH[1]}"$'\n'
                result+="${p}value ${BASH_REMATCH[2]}"$'\n'
            else
                in_coef=0
            fi
            continue
        fi
        if [[ $in_imp -eq 1 ]]; then
            [[ -z "${line//[[:space:]]/}" ]] && { in_imp=0; continue; }
            if [[ "$line" =~ $_doeo_re_imp ]]; then
                n=$((n + 1))
                local q="entry${n}."
                result+="${q}section importance"$'\n'
                result+="${q}response ${response}"$'\n'
                result+="${q}rank ${BASH_REMATCH[1]}"$'\n'
                result+="${q}term ${BASH_REMATCH[2]}"$'\n'
                result+="${q}effect ${BASH_REMATCH[3]}"$'\n'
                result+="${q}pct_contribution ${BASH_REMATCH[4]}"$'\n'
            else
                in_imp=0
            fi
            continue
        fi
    done <<< "$text"

    if [[ ${#responses[@]} -gt 0 ]]; then
        local joined="" r
        for r in "${responses[@]}"; do
            [[ -n "$joined" ]] && joined+=","
            joined+="$r"
        done
        result+="responses ${joined}"$'\n'
    fi
    result+="total_entries ${n}"$'\n'
    printf '%s' "$result"
}
