#!/bin/bash
## Name: kubectl-get-all
## Description: Parse `kubectl get all` multi-section output — one record per resource kind
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/kubectl-get-all/basic.txt

# `kubectl get all` prints one section per resource kind, each led by a "NAME ..."
# header and separated by blank lines:
#   NAME  READY STATUS ...        (pods)
#   pod/web-...  1/1 Running ...
#   <blank>
#   NAME  TYPE  CLUSTER-IP ...     (services)
#   service/... ...
# One record per section (resource kind): its kind, the number of resources, and
# their names. Section headers and blank lines are skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"pod/"* ]] || return 1
    [[ "$text" == *"service/"* ]] || return 1
    [[ "$text" == *"NAME"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        function flush(){
            if (open){
                e++
                print "entry" e ".kind " (kind==""?"-":kind)
                print "entry" e ".count " cnt
                print "entry" e ".names " (names==""?"-":names)
            }
            open=0; kind=""; cnt=0; names=""
        }
        {
            if ($1=="NAME") { flush(); open=1; next }   # section header
            if ($0 ~ /^[ \t]*$/) next
            if (!open) next
            name=$1
            k=name; sub(/\/.*$/,"",k)                   # kind: text before first /
            rn=name; sub(/^[^\/]*\//,"",rn)             # resource name: after first /
            if (kind=="") kind=k
            cnt++
            names=names (names==""?"":"_") rn
        }
        END{ flush(); if(e>0) print "total_entries " e }
    '
}
