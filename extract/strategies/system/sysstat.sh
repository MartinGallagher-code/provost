#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: sysstat
## Description: sysstat tools (mpstat, sar, pidstat) — banner + timestamped table
## Version: 1.0
## Priority: 40
## Commands: sar mpstat pidstat
## Sample: samples/sysstat/basic.txt

strategy_detect () {
    local text="$1"; _STRATEGY_CONFIDENCE=0
    local line first_seen=0 banner_ok=0 time_ok=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Skip blank / whitespace-only lines.
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ $first_seen -eq 0 ]]; then
            first_seen=1
            # The first non-blank line must be a sysstat banner: begins with a
            # kernel name (a letter) and ends with "(N CPU)".
            if [[ "$line" =~ ^[A-Za-z].*\([0-9]+\ CPU\)[[:space:]]*$ ]]; then
                banner_ok=1
                continue
            fi
            return 1
        fi
        # A later line whose first token is a HH:MM:SS timestamp.
        if [[ "$line" =~ ^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
            time_ok=1
        fi
    done

    if [[ $banner_ok -eq 1 && $time_ok -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"; local result="" entry=0
    local line first_seen=0 got_header=0
    local -a cols=()

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue

        # First non-blank line is the banner — skip it.
        if [[ $first_seen -eq 0 ]]; then
            first_seen=1
            continue
        fi

        local -a toks=()
        { _fr_tok "$line"; toks=("${_FR_TOK[@]}"); }
        [[ ${#toks[@]} -eq 0 ]] && continue

        # Leading HH:MM:SS timestamp (optionally followed by AM/PM) is the time.
        local timeval offset
        if [[ "${toks[0]}" =~ ^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$ ]]; then
            timeval="${toks[0]}"; offset=1
            if [[ "${toks[1]:-}" == "AM" || "${toks[1]:-}" == "PM" ]]; then
                timeval="${toks[0]} ${toks[1]}"; offset=2
            fi
        else
            continue
        fi

        # First timestamped line is the column header.
        if [[ $got_header -eq 0 ]]; then
            got_header=1
            cols=()
            local i
            for ((i=offset; i<${#toks[@]}; i++)); do
                cols+=("$(_strat_sysstat_sanitize "${toks[$i]}")")
            done
            continue
        fi

        # Data row -> one record.
        entry=$((entry + 1))
        result+="entry${entry}.time ${timeval}"$'\n'
        local i ci=0
        for ((i=offset; i<${#toks[@]}; i++)); do
            local col="${cols[$ci]:-col${ci}}"
            result+="entry${entry}.${col} ${toks[$i]}"$'\n'
            ci=$((ci + 1))
        done
    done

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}

# Sanitise a header token to a field name of letters/digits/underscore only.
# %usr -> pct_usr ; kB_read/s -> kB_read_s ; anything else non-word -> _.
_strat_sysstat_sanitize () {
    local col="$1"
    col="${col//%/pct_}"      # percent sign -> pct_
    col="${col//\//_}"        # slash -> underscore
    col="${col//[^A-Za-z0-9_]/_}"  # any remaining non-word char -> underscore
    echo "$col"
}
