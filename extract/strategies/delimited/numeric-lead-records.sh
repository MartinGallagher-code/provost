#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: numeric-lead-records
## Description: `PID command args...` process listings (pgrep -a, ps h) -> id/value rows
## Version: 1.0
## Priority: 57
## Sample: samples/numeric-lead-records/basic.txt

# Every line is an integer id then free text:
#
#   1843 /usr/sbin/mysqld --datadir=/var/lib/mysql
#   9021 php-fpm: pool www
#
# The id is a column; the rest is the command — the reviewer's "you didn't
# try" on pgrep -a. Gates: EVERY non-blank line is `digits SPACE rest`,
# unindented (uniq -c / wc -l count columns are right-aligned with leading
# spaces and stay with their own parsers), no tabs, no 2+-space runs (that
# gap means an aligned table), >=3 lines, and at least two DISTINCT ids
# (repeated ids would be a grouped log, not a listing).
strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line nb=0 ids="" distinct=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        [[ "$line" == [' 	']* ]] && return 1
        [[ "$line" == *'	'* ]] && return 1
        [[ "$line" == *'  '* ]] && return 1
        [[ "$line" =~ ^([0-9]+)\ (.+)$ ]] || return 1
        # The value is a command/path, not arithmetic: samtools flagstat's
        # `8821004 + 0 in total` leads its value with `+`. Require the first
        # value char to be a path, a program name, or a `[bracket]`.
        [[ "${BASH_REMATCH[2]}" == [/A-Za-z[]* ]] || return 1
        nb=$((nb + 1))
        case "$ids" in *"|${BASH_REMATCH[1]}|"*) ;; *) ids+="|${BASH_REMATCH[1]}|"; distinct=$((distinct + 1)) ;; esac
    done
    [[ $nb -ge 3 && $distinct -ge 2 ]] || return 1
    # General-structure tier (extract/README.md "Confidence rubric"): a
    # numeric first token is a shape, not a syntax — a real column-aligned
    # table over the same lines (aligned-columns >= 60) wins the tie.
    _STRATEGY_CONFIDENCE=60
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ ^([0-9]+)\ (.+)$ ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.id ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.value ${BASH_REMATCH[2]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
