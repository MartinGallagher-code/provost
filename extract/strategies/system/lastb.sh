#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: lastb
## Description: Extract failed login attempts from `lastb` output
## Version: 1.0
## Priority: 20
## Sample: samples/lastb/basic.txt

# `lastb` prints one row per bad login:
#   user  ssh:notty  1.2.3.4  Mon Jul  6 10:01 - 10:01  (00:00)
# followed by a trailing "btmp begins ..." footer.

_lastb_is_login () {
    [[ "$1" =~ ^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[[:space:]]+(Mon|Tue|Wed|Thu|Fri|Sat|Sun)[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # lastlog's table opens with a "Username Port From Latest" header and its
    # data rows mimic lastb's login lines — that table belongs to
    # aligned-columns, not lastb (which has no header).
    case "$text" in Username[[:space:]]*) return 1 ;; esac
    local line
    # PREFILTER (exact): a login line carries a whitespace-delimited weekday.
    [[ "$text" == *[[:space:]]Mon[[:space:]]* || "$text" == *[[:space:]]Tue[[:space:]]* \
       || "$text" == *[[:space:]]Wed[[:space:]]* || "$text" == *[[:space:]]Thu[[:space:]]* \
       || "$text" == *[[:space:]]Fri[[:space:]]* || "$text" == *[[:space:]]Sat[[:space:]]* \
       || "$text" == *[[:space:]]Sun[[:space:]]* ]] || return 1
    # `last` (wtmp) prints the same login lines, but a FAILED login (btmp) never
    # has an open session or a reboot pseudo-entry — those mark `last` output,
    # which this parser cannot shape (aligned-columns tidies it).
    [[ "$text" == *"still logged in"* || "$text" == *"still running"* \
       || "$text" == *"system boot"* ]] && return 1
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # A btmp entry always closes with its "(HH:MM)" duration — required, so
        # a table that merely holds "<name> <word> <IPv4> <weekday>" cells
        # (smbstatus shares: "projects 812 10.0.1.4 Thu Jul 10 …") declines.
        if _lastb_is_login "$line" && [[ "$line" =~ \([0-9+:]+\)[[:space:]]*$ ]]; then
            # 88: distinctive, but `last` prints the same line shape.
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _lastb_is_login "$line" || continue
        { _fr_tok "$line"; _a=("${_FR_TOK[@]}"); }
        local user="${_a[0]}" terminal="${_a[1]}" host="${_a[2]}"
        # The remainder is "<weekday date time> - <time>  (dur)".
        local rest="${line#*"$host"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        # duration is the trailing (..) token; when is everything before it.
        local duration="" when="$rest"
        if [[ "$rest" =~ \(([^\)]*)\)[[:space:]]*$ ]]; then
            duration="${BASH_REMATCH[1]}"
            when="${rest%(*}"
            when="${when%"${when##*[![:space:]]}"}"
        fi
        entry=$((entry + 1))
        result+="entry${entry}.user ${user}"$'\n'
        result+="entry${entry}.terminal ${terminal}"$'\n'
        result+="entry${entry}.host ${host}"$'\n'
        result+="entry${entry}.when ${when}"$'\n'
        [[ -n "$duration" ]] && result+="entry${entry}.duration ${duration}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
