#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: subject-field-value
## Description: `<subject> <field>:` label lines with the value on the NEXT line -> subject/field/value rows — hint-routed
## Version: 1.0
## Priority: 46
## Sample: samples/subject-field-value/basic.txt

# `apk info -a` labels every field with the package it belongs to and puts the
# value on the line BELOW the label:
#
#   busybox-1.36.1-r5 description:
#   Size optimized toolbox of many common UNIX utilities
#
#   busybox-1.36.1-r5 webpage:
#   https://busybox.net/
#
# A key/value parser reads that as five rows keyed
# `busybox-1.36.1-r5 description`, `busybox-1.36.1-r5 webpage`, … — the package
# name repeated inside every key, which is the reviewer's granularity note:
# a value that is the same on every row is a COLUMN, not part of the key.
#
#   subject             field           value
#   busybox-1.36.1-r5   description     Size optimized toolbox of …
#   busybox-1.36.1-r5   webpage         https://busybox.net/
#
# The subject is only split out when EVERY label shares the same leading token
# AND that token looks like an IDENTIFIER — it carries a digit or `-`/`.`/`_`.
# A shared plain word is English, not a subject: a cheat sheet whose entries all
# begin `To find …` would otherwise have `To` promoted to a column. When no
# subject is factored the whole label is the field, which is also what happens
# when the leading token varies.
#
# A leading `#` is stripped from the label, so a commented cheat sheet is the
# same shape as `apk info -a`:
#
#   # To find files by name:      ->   field  To find files by name
#   find . -name '*.log'               value  find . -name '*.log'
#
# HINT-ONLY: label-then-value layouts are far too common to auto-fire safely.

strategy_extract () {
    local text="$1"
    local line
    local -a labels=() values=()
    local pending=""
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        if [[ -z "$s" ]]; then continue; fi
        if [[ -n "$pending" ]]; then
            labels+=("$pending"); values+=("$s"); pending=""
            continue
        fi
        # A label line: ends in `:`, and the colon is only at the end (a
        # `key: value` line is somebody else's shape, not this one).
        if [[ "$s" == *: && "${s%:}" != *:* ]]; then
            local lbl="${s%:}"
            lbl="${lbl#\#}"
            lbl="${lbl#"${lbl%%[![:space:]]*}"}"
            [[ -n "$lbl" ]] && pending="$lbl"
        fi
    done

    local n=${#labels[@]}
    [[ $n -ge 2 ]] || return 0

    # Do all labels share one leading token, with something left after it?
    local subject="" common=1 i first
    first="${labels[0]%% *}"
    for ((i = 0; i < n; i++)); do
        if [[ "${labels[$i]%% *}" != "$first" || "${labels[$i]}" == "$first" ]]; then
            common=0; break
        fi
    done
    # A shared token that is nothing but letters is an English word, not a
    # subject (`To find files …`). Require identifier punctuation or a digit.
    [[ "$first" == *[0-9]* || "$first" == *[-._]* ]] || common=0
    [[ $common -eq 1 ]] && subject="$first"

    local result="" entry=0 field
    for ((i = 0; i < n; i++)); do
        field="${labels[$i]}"
        [[ -n "$subject" ]] && field="${field#"$subject" }"
        entry=$((entry + 1))
        [[ -n "$subject" ]] && result+="entry${entry}.subject ${subject}"$'\n'
        result+="entry${entry}.field ${field}"$'\n'
        result+="entry${entry}.value ${values[$i]}"$'\n'
    done
    result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
