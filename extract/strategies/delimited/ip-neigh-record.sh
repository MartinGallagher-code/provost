#!/bin/bash
## Name: ip-neigh-record
## Description: `ADDR dev IF lladdr MAC [flags] STATE` neighbour lines (ip -6 neigh) -> address/dev/lladdr/state rows — hint-routed
## Version: 1.0
## Priority: 45
## Sample: samples/ip-neigh-record/basic.txt

# `ip neigh` / `ip -6 neigh` print one neighbour per line as an address
# followed by keyword/value pairs and a trailing NUD state:
#
#   fe80::1 dev eth0 lladdr 00:1a:2b:3c:4d:5e router REACHABLE
#   2001:db8::ff dev eth0 lladdr 52:54:00:12:34:56 STALE
#   ::1 dev lo NOARP
#
# It stayed one opaque cell (the `fe80::1` colons defeat the colon parser, the
# keyword/value interleave defeats the column parsers). The tidy form pulls the
# address, the `dev` interface, the `lladdr` MAC (absent for some entries), and
# the trailing UPPERCASE state into their own columns; a bare `router` flag is
# dropped as it is neither:
#
#   address       dev    lladdr               state
#   fe80::1       eth0   00:1a:2b:3c:4d:5e    REACHABLE
#   2001:db8::ff  eth0   52:54:00:12:34:56    STALE
#   ::1           lo                          NOARP
#
# HINT-ONLY: routes on the `ADDR dev IF` shape via hints.tsv.

_ipn_dev_re='(^| )dev ([^ ]+)'
_ipn_lla_re='(^| )lladdr ([^ ]+)'
_ipn_state_re=' ([A-Z][A-Z_]+)[[:space:]]*$'

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        local addr="${s%%[[:space:]]*}"
        [[ -z "$addr" || "$addr" == "$s" ]] && return 0
        local dev="" lladdr="" state=""
        [[ "$s" =~ $_ipn_dev_re ]] && dev="${BASH_REMATCH[2]}"
        [[ "$s" =~ $_ipn_lla_re ]] && lladdr="${BASH_REMATCH[2]}"
        [[ "$s" =~ $_ipn_state_re ]] && state="${BASH_REMATCH[1]}"
        entry=$((entry + 1))
        result+="entry${entry}.address ${addr}"$'\n'
        result+="entry${entry}.dev ${dev}"$'\n'
        result+="entry${entry}.lladdr ${lladdr}"$'\n'
        result+="entry${entry}.state ${state}"$'\n'
    done <<< "$text"
    [[ $entry -ge 1 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
