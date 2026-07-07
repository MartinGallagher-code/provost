#!/bin/bash
## Name: networkctl-lldp
## Description: Parse `networkctl lldp` neighbor table (LINK CHASSIS ID SYSTEM NAME CAPS PORT ID PORT DESCRIPTION)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/networkctl-lldp/basic.txt

# `networkctl lldp` prints a neighbor table, then a blank line and a "Capability
# Flags:" legend. The table row is:
#   LINK CHASSIS-ID SYSTEM-NAME CAPS PORT-ID PORT-DESCRIPTION...
# (PORT DESCRIPTION may contain spaces). We read rows after the header until the
# first blank line, so the legend is never parsed. One record per neighbor.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"CHASSIS ID"* ]] || return 1
    [[ "$text" == *"PORT ID"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        BEGIN{ started=0 }
        {
            if ($0 ~ /LINK[ \t]+CHASSIS ID/) { started=1; next }
            if (!started) next
            if ($0 ~ /^[ \t]*$/) { started=0; next }   # blank ends the table
            if (NF < 5) next
            link=$1; chassis=$2; sysname=$3; caps=$4; portid=$5
            pdesc=""
            for(i=6;i<=NF;i++) pdesc=pdesc (i>6?"_":"") $i
            e++
            print "entry" e ".link " link
            print "entry" e ".chassis_id " chassis
            print "entry" e ".system_name " sysname
            print "entry" e ".caps " caps
            print "entry" e ".port_id " portid
            print "entry" e ".port_description " (pdesc==""?"-":pdesc)
        }
        END{ if(e>0) print "total_entries " e }
    '
}
