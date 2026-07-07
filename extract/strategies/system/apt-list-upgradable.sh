#!/bin/bash
## Name: apt-list-upgradable
## Description: Parse `apt list --upgradable` lines (pkg/repo version arch [upgradable from: ...])
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/apt-list-upgradable/basic.txt

# `apt list --upgradable` prints a "Listing..." header then one line per package:
#   libssl3/jammy-security 3.0.2-0ubuntu1.15 amd64 [upgradable from: 3.0.2-0ubuntu1.12]
# The first token is "package/repo", followed by the candidate version, the arch,
# and a "[upgradable from: OLD]" note. One record per package.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"[upgradable from:"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        /\[upgradable from:/ {
            pkgrepo=$1; ver=$2; arch=$3
            n=split(pkgrepo, pr, "/")
            pkg=pr[1]; repo=(n>=2?pr[2]:"-")
            from=$0
            sub(/^.*upgradable from:[ \t]*/,"",from); sub(/\].*$/,"",from)
            gsub(/[ \t]+/,"_",from)
            e++
            print "entry" e ".package " pkg
            print "entry" e ".repo " repo
            print "entry" e ".version " ver
            print "entry" e ".arch " arch
            print "entry" e ".upgradable_from " (from==""?"-":from)
        }
        END{ if(e>0) print "total_entries " e }
    '
}
