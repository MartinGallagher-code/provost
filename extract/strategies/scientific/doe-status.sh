#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: doe-status
## Description: Extract per-run progress from `doe status` output (doehelper), one row per experiment run
## Version: 1.0
## Priority: 22
## Sample: samples/doe-status/basic.txt

# `doe status` prints an `Experiment:`/`Design:` header, a progress bar, then
# `Completed runs:` and/or `Pending runs:` sections listing one run each:
#
#   Completed runs:
#     Run 1: temperature=100, pressure=1, catalyst=C
#
# Each run's factor settings are `name=value` pairs, so they become their own
# columns rather than one opaque string. Generic `block-records` turned the
# twelve runs into twelve COLUMNS of a single row (plus a duplicate set of
# mangled `Run_N:_temperature` columns); one row per run is the tidy shape.
_does_re_exp='^Experiment:[[:space:]]*(.*)$'
_does_re_design='^Design:[[:space:]]*(.*)$'
_does_re_prog='^Progress:[[:space:]]*([0-9]+)/([0-9]+)[[:space:]]+complete.*[[:space:]]([0-9]+)%'
_does_re_run='^[[:space:]]+Run[[:space:]]+([0-9]+):[[:space:]]*(.*)$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == "Experiment:"* || "$text" == *$'\nExperiment:'* ]] || return 1
    [[ "$text" == *$'\nDesign:'* ]] || return 1
    [[ "$text" == *"Progress:"* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    _STRATEGY_CONFIDENCE_REASON="doe status header (Experiment/Design/Progress) present"
    return 0
}

_dost_trim () {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# Field-name-safe key: lowercase, non-alnum -> underscore.
_dost_key () {
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
    local result="" line n=0 state=""
    local experiment="" design="" done_n="" total_n="" pct=""

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" =~ $_does_re_exp ]]; then
            experiment="$(_dost_trim "${BASH_REMATCH[1]}")"; continue
        fi
        if [[ "$line" =~ $_does_re_design ]]; then
            design="$(_dost_trim "${BASH_REMATCH[1]}")"; continue
        fi
        if [[ "$line" =~ $_does_re_prog ]]; then
            done_n="${BASH_REMATCH[1]}"; total_n="${BASH_REMATCH[2]}"; pct="${BASH_REMATCH[3]}"
            continue
        fi
        # Section headers switch which status the following runs carry.
        case "$line" in
            "Completed runs:"*) state="completed"; continue ;;
            "Pending runs:"*)   state="pending";   continue ;;
            # `Next run to complete: Run N` opens an indented factor list that
            # repeats a run already listed above — don't double-count it.
            "Next run to complete:"*) state=""; continue ;;
        esac
        if [[ -n "$state" && "$line" =~ $_does_re_run ]]; then
            n=$((n + 1))
            local p="entry${n}."
            result+="${p}run_id ${BASH_REMATCH[1]}"$'\n'
            result+="${p}status ${state}"$'\n'
            # Split `name=value, name=value` into one column per factor.
            local rest="${BASH_REMATCH[2]}" pair k v
            local oldifs="$IFS"
            IFS=','
            for pair in $rest; do
                pair="$(_dost_trim "$pair")"
                [[ "$pair" != *"="* ]] && continue
                k="$(_dost_key "$(_dost_trim "${pair%%=*}")")"
                v="$(_dost_trim "${pair#*=}")"
                result+="${p}${k} ${v}"$'\n'
            done
            IFS="$oldifs"
            continue
        fi
        # A blank line closes the current section.
        [[ "${line}" != *[![:space:]]* ]] && state=""
    done

    [[ -n "$experiment" ]] && result+="experiment ${experiment}"$'\n'
    [[ -n "$design" ]]     && result+="design ${design}"$'\n'
    [[ -n "$done_n" ]]     && result+="runs_complete ${done_n}"$'\n'
    [[ -n "$total_n" ]]    && result+="runs_total ${total_n}"$'\n'
    [[ -n "$pct" ]]        && result+="percent_complete ${pct}"$'\n'
    result+="total_entries ${n}"$'\n'
    printf '%s' "$result"
}
