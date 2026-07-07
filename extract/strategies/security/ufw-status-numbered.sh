#!/bin/bash
## Name: ufw-status-numbered
## Description: Parse `ufw status numbered` rules ([N] To Action From)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/ufw-status-numbered/basic.txt

# `ufw status numbered` prints a "Status: active" line, a "To Action From"
# header block, then numbered rules:
#   [ 1] 22/tcp                     ALLOW IN    Anywhere
# The To/Action/From columns are separated by runs of 2+ spaces (Action itself
# is "ALLOW IN"/"DENY IN" and To/From can contain "(v6)"), so we split on 2+
# spaces after stripping the "[N]" index. One record per rule.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Status:"* ]] || return 1
    [[ "$text" == *"ALLOW IN"* || "$text" == *"DENY IN"* || "$text" == *"Action"*"From"* ]] || return 1
    [[ "$text" == *"["*"]"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        function san(s){ gsub(/^[ \t]+/,"",s); gsub(/[ \t]+$/,"",s); gsub(/[ \t]+/,"_",s); return s }
        {
            # Only numbered rule rows: "[ N] ..."
            if ($0 !~ /^[ \t]*\[[ \t]*[0-9]+\]/) next
            line=$0
            num=$0; sub(/^[ \t]*\[[ \t]*/,"",num); sub(/\].*$/,"",num)
            rest=line; sub(/^[ \t]*\[[ \t]*[0-9]+\][ \t]*/,"",rest)
            # Split remaining columns on runs of 2+ spaces.
            n=split(rest, col, /  +/)
            to=(n>=1?col[1]:""); action=(n>=2?col[2]:""); from=(n>=3?col[3]:"")
            e++
            print "entry" e ".num " num
            print "entry" e ".to " san(to)
            print "entry" e ".action " san(action)
            print "entry" e ".from " san(from)
        }
        END{ if(e>0) print "total_entries " e }
    '
}
