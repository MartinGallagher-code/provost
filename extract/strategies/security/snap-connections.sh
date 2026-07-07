#!/bin/bash
## Name: snap-connections
## Description: Parse `snap connections` table (Interface Plug Slot Notes)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/snap-connections/basic.txt

# `snap connections` prints a whitespace-aligned table:
#   Interface  Plug  Slot  Notes
# with no internal spaces in any cell. One record per connection row; the header
# is skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Interface"*"Plug"*"Slot"*"Notes"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        {
            if ($0 ~ /^[ \t]*$/) next
            if ($1=="Interface") next
            if (NF < 2) next
            iface=$1; plug=$2; slot=(NF>=3?$3:"-"); notes=(NF>=4?$4:"-")
            e++
            print "entry" e ".interface " iface
            print "entry" e ".plug " plug
            print "entry" e ".slot " slot
            print "entry" e ".notes " notes
        }
        END{ if(e>0) print "total_entries " e }
    '
}
