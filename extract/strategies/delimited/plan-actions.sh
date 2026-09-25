#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: plan-actions
## Description: terraform plan `# resource will be ACTION` comment lines -> resource/action rows
## Version: 1.0
## Priority: 39
## Sample: samples/plan-actions/basic.txt

# terraform's plan preview names each pending change in a `#` comment line:
#
#   # aws_db_instance.primary will be updated in-place
#   # aws_instance.app_server will be created
#   Plan: 3 to add, 1 to change, 1 to destroy.
#
# block-records kept only the `Plan:` summary pair and dropped every resource
# line — the reviewer's "you lost information". The resource lines are the
# data; each splits on the literal `will be` into resource | action:
#
#   resource                  action
#   aws_db_instance.primary   updated in-place
#   aws_instance.app_server   created
#
# Detection: >=2 lines of the exact `# NAME will be …` shape. The `#`-lead
# plus the `will be` phrase together are the signature; `#` comment banners
# without it never match.

_pa_re='^[[:space:]]*#[[:space:]]+([^[:space:]]+)[[:space:]]will[[:space:]]be[[:space:]](.+)$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ $_pa_re ]] && n=$((n + 1))
    done
    [[ $n -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 action
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ $_pa_re ]] || continue
        action="${BASH_REMATCH[2]}"
        action="${action%"${action##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.resource ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.action ${action}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
