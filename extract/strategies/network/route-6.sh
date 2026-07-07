#!/bin/bash
## Name: route-6
## Description: Parse `route -A inet6 -n` IPv6 routing table (Destination Next Hop Flag Met Ref Use If)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/route-6/basic.txt

# `route -A inet6 -n` prints a banner ("Kernel IPv6 routing table"), a column
# header ("Destination Next Hop Flag Met Ref Use If"), then one route per line.
# Each cell is a single whitespace-delimited token. One record per route; the
# banner and header are skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Kernel IPv6 routing table"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        {
            if ($0 ~ /^[ \t]*$/) next
            if ($0 ~ /Kernel IPv6 routing table/) next
            if ($1=="Destination") next
            if (NF < 4) next
            e++
            print "entry" e ".destination " $1
            print "entry" e ".next_hop " $2
            print "entry" e ".flag " $3
            print "entry" e ".met " (NF>=4?$4:"-")
            print "entry" e ".ref " (NF>=5?$5:"-")
            print "entry" e ".use " (NF>=6?$6:"-")
            print "entry" e ".iface " (NF>=7?$7:"-")
        }
        END{ if(e>0) print "total_entries " e }
    '
}
