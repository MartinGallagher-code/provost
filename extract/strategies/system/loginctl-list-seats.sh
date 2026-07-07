#!/bin/bash
## Name: loginctl-list-seats
## Description: Parse `loginctl list-seats` single-column seat list
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/loginctl-list-seats/basic.txt

# `loginctl list-seats` prints a "SEAT" header, one seat id per line, a blank
# line, and an "N seats listed." footer. Single-column output: one record per
# seat (entryN.c1).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"SEAT"* ]] || return 1
    [[ "$text" == *"seats listed"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        {
            if ($0 ~ /^[ \t]*$/) next
            if ($1=="SEAT") next
            if ($0 ~ /seats listed/) next
            if (NF < 1) next
            e++
            print "entry" e ".c1 " $1
        }
        END{ if(e>0) print "total_entries " e }
    '
}
