#!/bin/bash
## Name: perf-counters
## Description: `perf stat` counter table → one tidy row per counter (count, event)
## Version: 1.0
## Priority: 18
## Sample: samples/perf-counters/basic.txt

# `perf stat` prints a "Performance counter stats for '<cmd>'" banner followed by
# one line per counter:
#     8,412.33 msec task-clock            #    0.842 CPUs utilized
#        1,204      context-switches      #  143.121 /sec
# and a trailing "N seconds time elapsed" summary. Each counter line begins with
# a (comma-grouped) number and ends — before any "#" annotation — with the event
# identifier. Tidied to one row per counter: (count, event).

_pc_is_counter () {
    # Leading spaces, then a number (comma/dot ok), then whitespace. Excludes the
    # banner (starts with a letter) and blank lines.
    [[ "$1" =~ ^[[:space:]]*[0-9][0-9,\.]*[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Performance counter stats for"* ]] || return 1
    local line
    while IFS= read -r line; do
        _pc_is_counter "$line" && { _STRATEGY_CONFIDENCE=86; return 0; }
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        _pc_is_counter "$line" || continue
        # Drop the trailing "N seconds time elapsed" wall-clock summary.
        [[ "$line" == *"time elapsed"* ]] && continue
        # Keep only the counter portion, before any "#" annotation.
        local body="${line%%#*}"
        local toks; toks=(); read -ra toks <<< "$body"
        local ntok=${#toks[@]}
        [[ $ntok -ge 2 ]] || continue
        local count="${toks[0]}"
        count="${count//,/}"
        local event="${toks[$((ntok - 1))]}"
        entry=$((entry + 1))
        result+="entry${entry}.count ${count}"$'\n'
        result+="entry${entry}.event ${event}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
