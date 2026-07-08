#!/bin/bash
## Name: cloud-json-list
## Description: Parse a top-level JSON array from cloud CLIs (az/gcloud list) — one record per element
## Version: 1.0
## Priority: 8
## Technique: yes
## Sample: samples/cloud-json-list/basic.txt

# Merged parser for cloud-CLI `list --format=json` commands that emit a top-level
# JSON array of flat objects. All share one extraction (walk the array by brace
# depth, emit one record per element with its flat scalar fields), so they need
# only distinct detect guards, OR-ed together here:
#   az account list      — "cloudName" + "tenantId"
#   az acr list          — "loginServer" + "adminUserEnabled"
#   az keyvault list     — Microsoft.KeyVault/vaults
#   gcloud pubsub topics list — "/topics/" + "messageRetentionDuration"
# Each guard is specific enough to beat the generic `json` parser only for its
# own command's output.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local t="${text#"${text%%[![:space:]]*}"}"   # strip leading whitespace
    [[ "$t" == '['* ]] || return 1
    if [[ "$text" == *'"cloudName"'* && "$text" == *'"tenantId"'* ]] \
       || [[ "$text" == *'"loginServer"'* && "$text" == *'"adminUserEnabled"'* ]] \
       || [[ "$text" == *'Microsoft.KeyVault/vaults'* ]] \
       || [[ "$text" == *'/topics/'* && "$text" == *'"messageRetentionDuration"'* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
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
