#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: masscan
## Description: Parse masscan "Discovered open port PORT/PROTO on IP" lines
## Version: 1.0
## Priority: 22
## Sample: samples/masscan/basic.txt

# masscan prints a banner and progress lines, then one discovery line per open
# port:
#   Discovered open port 443/tcp on 192.0.2.10
# One record per discovery; banner/progress lines are ignored.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Discovered open port"* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        /Discovered open port/ {
            # Discovered open port 443/tcp on 192.0.2.10
            portproto=$4; ip=$6
            n=split(portproto, pp, "/")
            port=pp[1]; proto=(n>=2?pp[2]:"-")
            e++
            print "entry" e ".state open"
            print "entry" e ".port " port
            print "entry" e ".proto " proto
            print "entry" e ".ip " ip
        }
        END{ if(e>0) print "total_entries " e }
    '
}
