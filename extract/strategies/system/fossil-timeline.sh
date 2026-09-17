#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: fossil-timeline
## Description: Extract checkins from a Fossil `fossil timeline`
## Version: 1.0
## Priority: 22
## Sample: samples/fossil-timeline/basic.txt

# `fossil timeline` groups entries under `=== DATE ===` banners:
#   10:15:42 [a1b2c3d4e5] Add login form validation (user: alice tags: trunk)
# One record per timed checkin; banners and the `--- entry limit ---` footer
# are skipped.

_fossiltl_is_entry () {
    [[ "$1" =~ ^[0-9][0-9]:[0-9][0-9]:[0-9][0-9][[:space:]]\[ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has=0
    while IFS= read -r line; do
        _fossiltl_is_entry "$line" && has=1
    done <<< "$text"
    if [[ $has -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line timev hash rest message user
    while IFS= read -r line; do
        _fossiltl_is_entry "$line" || continue
        timev="${line%%[[:space:]]*}"
        hash="${line#*[}"
        hash="${hash%%]*}"
        rest="${line#*] }"
        message="${rest%% (user:*}"
        if [[ "$line" == *"(user: "* ]]; then
            user="${line#*(user: }"
            user="${user%% *}"
            user="${user%)}"
        else
            user=""
        fi
        message="${message//$'\t'/_}"
        entry=$((entry + 1))
        result+="entry${entry}.time ${timev}"$'\n'
        result+="entry${entry}.hash ${hash}"$'\n'
        result+="entry${entry}.message ${message}"$'\n'
        result+="entry${entry}.user ${user}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
