#!/bin/bash
## Name: progress-ledger
## Description: dbt-style `HH:MM:SS  N of M OP subject ..... [STATUS]` progress lines -> time/seq/operation/subject/status
## Version: 1.0
## Priority: 42
## Sample: samples/progress-ledger/basic.txt

# dbt (run, test, source freshness) prints one ledger line per step:
#
#   14:05:02  1 of 3 START freshness of raw.events ..................... [RUN]
#   14:05:04  1 of 3 PASS freshness of raw.events ..................... [PASS in 2.10s]
#   14:05:09  3 of 3 ERROR STALE freshness of raw.sessions ............ [ERROR STALE in 2.44s]
#
# The reviewer's columns: the time, the `N of M` counter, the operation (the
# leading ALL-CAPS run — START, PASS, ERROR STALE), the subject between the
# operation and the dot leader, and the bracket body with the brackets
# dropped. The dots are padding and go:
#
#   time      seq     operation    subject                  status
#   14:05:02  1 of 3  START        freshness of raw.events  RUN
#   14:05:09  3 of 3  ERROR STALE  freshness of raw.sessions ERROR STALE in 2.44s
#
# Detection: every non-blank line matches the full shape (time, counter,
# caps op, subject, >=4-dot leader, bracketed tail).

_pl_re='^([0-9]{1,2}:[0-9]{2}:[0-9]{2})[[:space:]]+([0-9]+ of [0-9]+)[[:space:]]+(.+[^. ])[[:space:]]*\.\.\.\.+[[:space:]]*\[([^]]+)\][[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_pl_re ]] || return 1
        # The op+subject body must OPEN with an ALL-CAPS token.
        [[ "${BASH_REMATCH[3]}" =~ ^[A-Z]+([[:space:]]|$) ]] || return 1
        n=$((n + 1))
    done <<< "$text"
    [[ $n -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_pl_re ]] || continue
        local body="${BASH_REMATCH[3]}" t="${BASH_REMATCH[1]}" seq="${BASH_REMATCH[2]}" status="${BASH_REMATCH[4]}"
        # Operation = the leading run of ALL-CAPS tokens; subject = the rest.
        local -a tok=(); read -ra tok <<< "$body"
        local op="" i=0
        for ((i = 0; i < ${#tok[@]}; i++)); do
            [[ "${tok[$i]}" =~ ^[A-Z]+$ ]] || break
            op+="${op:+ }${tok[$i]}"
        done
        local subject="${tok[*]:$i}"
        entry=$((entry + 1))
        result+="entry${entry}.time ${t}"$'\n'
        result+="entry${entry}.seq ${seq}"$'\n'
        [[ -n "$op" ]] && result+="entry${entry}.operation ${op}"$'\n'
        [[ -n "$subject" ]] && result+="entry${entry}.subject ${subject}"$'\n'
        result+="entry${entry}.status ${status}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
