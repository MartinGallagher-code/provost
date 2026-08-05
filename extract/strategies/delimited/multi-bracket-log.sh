#!/bin/bash
## Name: multi-bracket-log
## Description: esphome-style glued `[time][level][tag]: message` log lines -> one column per bracket + message
## Version: 1.0
## Priority: 47
## Sample: samples/multi-bracket-log/basic.txt

# Some loggers glue SEVERAL bracket tags to the front of each line and close
# the prefix with a colon:
#
#   [06:00:00][I][sensor:094]: 'Living Temp': Sending state 21.4 °C
#   [06:00:05][D][api:102]: Client connected
#
# bracket-log expects ONE `[tag] ` then the message, so this fell to
# aligned-columns as token soup. The reviewer: "every set of square brackets
# is its own column; then everything after the colon is a single value":
#
#   A         B  C           message
#   06:00:00  I  sensor:094  'Living Temp': Sending state 21.4 °C
#   06:00:05  D  api:102     Client connected
#
# Only the PREFIX colon splits — colons inside the message stay. Detection:
# every non-blank line opens with >=2 glued brackets followed by `:` and a
# message.

_mbl_re='^(\[[^]]+\])(\[[^]]+\])+:[[:space:]]+[^[:space:]]'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_mbl_re ]] || return 1
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
        [[ "$line" =~ $_mbl_re ]] || continue
        entry=$((entry + 1))
        local rest="$line" i=0 col
        while [[ "$rest" == \[*\]* ]]; do
            local tag="${rest#\[}"
            tag="${tag%%]*}"
            rest="${rest#*]}"
            i=$((i + 1))
            col=$(printf "\\$(printf '%03o' $((64 + i)))")
            result+="entry${entry}.${col} ${tag}"$'\n'
        done
        # The prefix-closing colon, then the message (inner colons kept).
        rest="${rest#:}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        rest="${rest%"${rest##*[![:space:]]}"}"
        [[ -n "$rest" ]] && result+="entry${entry}.message ${rest}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
