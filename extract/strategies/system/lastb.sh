#!/bin/bash
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
    while IFS= read -r line; do
        if _lastb_is_login "$line"; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        _lastb_is_login "$line" || continue
        read -ra _a <<< "$line"
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
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
