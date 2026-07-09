#!/bin/bash
## Name: systemctl-list-units
## Description: Parse `systemctl list-units` unit table (UNIT LOAD ACTIVE SUB DESCRIPTION)
## Version: 1.0
## Priority: 22
## Sample: samples/systemctl-list-units/basic.txt

# `systemctl list-units` prints an aligned table:
#   UNIT  LOAD  ACTIVE  SUB  DESCRIPTION
# followed by a legend block and an "N loaded units listed." footer. One record
# per unit row; the header, legend and footer are skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Narrow signature: the distinctive column header + the footer line.
    [[ "$text" == *"UNIT"*"LOAD"*"ACTIVE"*"SUB"*"DESCRIPTION"* ]] || return 1
    [[ "$text" == *"loaded units listed"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        {
            if ($0 ~ /^[ \t]*$/) next
            if ($0 ~ /UNIT[ \t]+LOAD[ \t]+ACTIVE/) next
            if ($0 ~ /loaded units listed/) next
            if ($1=="LOAD" || $1=="ACTIVE" || $1=="SUB") next
            unit=$1; load=$2; active=$3; substate=$4
            desc=""
            for(i=5;i<=NF;i++) desc=desc (i>5?"_":"") $i
            e++
            print "entry" e ".unit " unit
            print "entry" e ".load " load
            print "entry" e ".active " active
            print "entry" e ".sub " substate
            print "entry" e ".description " (desc==""?"-":desc)
        }
        END{ if(e>0) print "total_entries " e }
    '
}
