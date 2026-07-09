#!/bin/bash
## Name: iptables-nat
## Description: Parse `iptables -t nat -L` rules (target prot opt source destination)
## Version: 1.0
## Priority: 22
## Sample: samples/iptables-nat/basic.txt

# `iptables -t nat -L` prints per-chain blocks:
#   Chain PREROUTING (policy ACCEPT)
#   target     prot opt source               destination
#   DNAT       tcp  --  anywhere             anywhere
#   ...
# One record per rule; the "Chain ..." headers and the "target prot opt ..."
# column headers are skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Chain "* ]] || return 1
    [[ "$text" == *"target"*"prot"*"opt"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        {
            if ($0 ~ /^[ \t]*$/) next
            if ($1=="Chain") next
            if ($1=="target" && $2=="prot") next
            if (NF < 4) next
            target=$1; prot=$2; opt=$3; src=$4; dst=(NF>=5?$5:"-")
            e++
            print "entry" e ".target " target
            print "entry" e ".prot " prot
            print "entry" e ".opt " opt
            print "entry" e ".source " src
            print "entry" e ".destination " dst
        }
        END{ if(e>0) print "total_entries " e }
    '
}
