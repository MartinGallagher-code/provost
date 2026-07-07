#!/bin/bash
## Name: az-account-list
## Description: Parse `az account list` JSON array — one record per subscription
## Version: 1.0
## Priority: 8
## Technique: yes
## Sample: samples/az-account-list/basic.txt

# `az account list` emits a top-level JSON array of subscription objects. We walk
# the array by brace depth (not a JSON guard) and emit one record per element,
# pulling the flat scalar fields (cloudName, id, isDefault, name, state,
# tenantId).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local t="${text#"${text%%[![:space:]]*}"}"   # strip leading whitespace
    [[ "$t" == '['* ]] || return 1
    [[ "$text" == *'"cloudName"'* ]] || return 1
    [[ "$text" == *'"tenantId"'* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        function scalar(v){
            gsub(/^[ \t]+/,"",v); gsub(/[ \t,]+$/,"",v)
            gsub(/^"/,"",v); gsub(/"$/,"",v)
            gsub(/[ \t]+/,"_",v)
            return v
        }
        {
            raw=$0
            t=raw; no=gsub(/\{/,"",t); t=raw; nc=gsub(/\}/,"",t)
            if (bd==0 && no>0) e++
            before=bd
            bd += no - nc
            if (before==1 && no==0 && nc==0) {
                if (match(raw, /"[^"]+"[ \t]*:/)) {
                    key=substr(raw, RSTART, RLENGTH)
                    sub(/^"/,"",key); sub(/".*$/,"",key)
                    val=raw; sub(/^[^:]*:[ \t]*/,"",val)
                    print "entry" e "." key " " scalar(val)
                }
            }
        }
        END{ if(e>0) print "total_entries " e }
    '
}
