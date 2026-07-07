#!/bin/bash
## Name: gcloud-pubsub-topics-list
## Description: Parse `gcloud pubsub topics list --format=json` array — one record per topic
## Version: 1.0
## Priority: 8
## Technique: yes
## Sample: samples/gcloud-pubsub-topics-list/basic.txt

# `gcloud pubsub topics list --format=json` emits a top-level JSON array of topic
# objects. We walk the array by brace depth and emit one record per element,
# pulling the flat scalar fields (name, messageRetentionDuration, kmsKeyName).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local t="${text#"${text%%[![:space:]]*}"}"
    [[ "$t" == '['* ]] || return 1
    [[ "$text" == *'/topics/'* ]] || return 1
    [[ "$text" == *'"messageRetentionDuration"'* ]] || return 1
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
