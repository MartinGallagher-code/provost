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
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Detect needs fossil's bracketed hex check-in hash ("10:15:42
        # [a1b2c3d4e5] …"): the extract helper's "HH:MM:SS [" prefix alone is
        # every bracket-tagged log line ("12:00:01 [INFO] …").
        _fossiltl_is_entry "$line" && [[ "$line" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]\[[0-9a-f]{6,40}\][[:space:]] ]] && has=1
    done
    if [[ $has -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=92
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line timev hash rest message user
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
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
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
