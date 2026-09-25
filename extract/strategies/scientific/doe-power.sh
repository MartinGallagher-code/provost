#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: doe-power
## Description: Extract the per-factor power table from `doe power` output (doehelper), one row per factor
## Version: 1.0
## Priority: 22
## Sample: samples/doe-power/basic.txt

# `doe power` prints an optional `Estimated sigma ...` line, a
# `=== Power Analysis ===` header, a key/value preamble, then the table:
#
#   Factor                   Levels  Power @ delta   MDE @ target
#   ------------------------ ------ -------------- --------------
#   temperature                   2          0.986         2.7561
#
# The table is the data; the preamble rides along as constant columns.
# Generic `block-records` was capturing only the preamble and dropping the
# factor rows entirely.
#
# Detection keys on the `=== Power Analysis ===` banner, which only the
# standalone `doe power` command emits — `doe analyze`'s embedded copy is
# headed `=== Achieved Power: <response> ===` and belongs to `doe-analyze`.
_doep_re_runs='^[[:space:]]+Runs:[[:space:]]*([0-9]+),[[:space:]]*df_error:[[:space:]]*([0-9]+)'
_doep_re_sigma='^[[:space:]]+Sigma[^:]*:[[:space:]]*([0-9.eE+-]+)'
_doep_re_resid='residual MS[[:space:]]*=[[:space:]]*([0-9.eE+-]+)'
_doep_re_alpha='^[[:space:]]+Alpha:[[:space:]]*([0-9.eE+-]+)'
_doep_re_delta='delta:[[:space:]]*([0-9.eE+-]+)'
_doep_re_target='target power:[[:space:]]*([0-9.eE+-]+)'
_doep_re_est='^Estimated sigma from residuals:[[:space:]]*([0-9.eE+-]+)'
_doep_re_rule='^[[:space:]]+-+[[:space:]-]*$'
# factor  levels  power  mde   (mde may be the literal `inf`)
_doep_re_row='^[[:space:]]+([^[:space:]].*[^[:space:]])[[:space:]]+([0-9]+)[[:space:]]+([0-9.eE+-]+)[[:space:]]+([0-9.eE+-]+|inf)[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"=== Power Analysis ==="* ]] || return 1
    [[ "$text" == *"Power @ delta"* ]] || return 1
    _STRATEGY_CONFIDENCE=88
    _STRATEGY_CONFIDENCE_REASON="doe power banner + per-factor power table header"
    return 0
}

_doep_trim () {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    printf '%s' "${s%"${s##*[![:space:]]}"}"
}

strategy_extract () {
    local text="$1"
    local result="" line n=0 in_table=0
    local runs="" df_error="" sigma="" residual_ms="" alpha="" delta="" target_power="" est_sigma=""

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Header/preamble — collected before (and regardless of) the table.
        if [[ "$line" =~ $_doep_re_est ]]; then
            est_sigma="${BASH_REMATCH[1]}"; continue
        fi
        if [[ "$line" =~ $_doep_re_runs ]]; then
            runs="${BASH_REMATCH[1]}"; df_error="${BASH_REMATCH[2]}"; continue
        fi
        if [[ "$line" =~ $_doep_re_sigma ]]; then
            sigma="${BASH_REMATCH[1]}"
            [[ "$line" =~ $_doep_re_resid ]] && residual_ms="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ $_doep_re_alpha ]]; then
            alpha="${BASH_REMATCH[1]}"
            [[ "$line" =~ $_doep_re_delta ]] && delta="${BASH_REMATCH[1]}"
            [[ "$line" =~ $_doep_re_target ]] && target_power="${BASH_REMATCH[1]}"
            continue
        fi
        # The column header opens the table; its rule line confirms it.
        if [[ "$line" == *"Power @ delta"* ]]; then
            in_table=1
            continue
        fi
        if [[ $in_table -eq 1 && "$line" =~ $_doep_re_rule ]]; then
            continue
        fi
        if [[ $in_table -eq 1 ]]; then
            # Blank line, or a trailing `Note:` line, ends the table.
            [[ "${line}" != *[![:space:]]* ]] && { in_table=0; continue; }
            if [[ "$line" =~ $_doep_re_row ]]; then
                n=$((n + 1))
                local p="entry${n}."
                result+="${p}factor $(_doep_trim "${BASH_REMATCH[1]}")"$'\n'
                result+="${p}levels ${BASH_REMATCH[2]}"$'\n'
                result+="${p}power_at_delta ${BASH_REMATCH[3]}"$'\n'
                result+="${p}mde_at_target ${BASH_REMATCH[4]}"$'\n'
            else
                # Anything else (e.g. the "Note: power < 0.80 ..." line) closes it.
                in_table=0
            fi
            continue
        fi
    done

    [[ -n "$runs" ]]         && result+="runs ${runs}"$'\n'
    [[ -n "$df_error" ]]     && result+="df_error ${df_error}"$'\n'
    [[ -n "$sigma" ]]        && result+="sigma ${sigma}"$'\n'
    [[ -n "$residual_ms" ]]  && result+="residual_ms ${residual_ms}"$'\n'
    [[ -n "$alpha" ]]        && result+="alpha ${alpha}"$'\n'
    [[ -n "$delta" ]]        && result+="delta ${delta}"$'\n'
    [[ -n "$target_power" ]] && result+="target_power ${target_power}"$'\n'
    [[ -n "$est_sigma" ]]    && result+="estimated_sigma ${est_sigma}"$'\n'
    result+="total_entries ${n}"$'\n'
    printf '%s' "$result"
}
