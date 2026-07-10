#!/bin/bash
## Name: systemd-tmpfiles-cat-config
## Description: Parse `systemd-tmpfiles --cat-config` lines (type path mode user group age arg)
## Version: 1.0
## Priority: 22
## Sample: samples/systemd-tmpfiles-cat-config/basic.txt

# `systemd-tmpfiles --cat-config` concatenates tmpfiles.d fragments. Comment
# lines (starting with '#', e.g. "# /usr/lib/tmpfiles.d/systemd.conf") and blank
# lines separate the fragments; each real line is a directive:
#   type path mode user group age argument
# One record per directive.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"tmpfiles.d"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        {
            if ($0 ~ /^[ \t]*$/) next
            if ($0 ~ /^[ \t]*#/) next
            if (NF < 2) next
            type=$1; path=$2
            mode=(NF>=3?$3:"-"); user=(NF>=4?$4:"-")
            group=(NF>=5?$5:"-"); age=(NF>=6?$6:"-")
            arg=""
            for(i=7;i<=NF;i++) arg=arg (i>7?"_":"") $i
            e++
            print "entry" e ".type " type
            print "entry" e ".path " path
            print "entry" e ".mode " mode
            print "entry" e ".user " user
            print "entry" e ".group " group
            print "entry" e ".age " age
            print "entry" e ".arg " (arg==""?"-":arg)
        }
        END{ if(e>0) print "total_entries " e }
    '
}
