#!/bin/bash
## Name: json-array
## Description: Top-level JSON array of objects — one record per element (az/gcloud/aws list, docker inspect)
## Version: 1.0
## Priority: 9
## Sample: samples/json-array/basic.txt

# A top-level JSON ARRAY of objects is a list of records; parsing it as one
# blob (the `json` strategy's 0.field/1.field flatten) buries that. This
# parser emits one record per array element with its top-level scalar
# fields — the natural tidy shape for every `<cli> list --format=json` and
# `docker inspect` style output. Nested objects/arrays inside an element are
# skipped (their scalars are not top-level fields of the record).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Structural: first non-space char is '[', the next non-space char is '{'
    # (an array of OBJECTS — not a bracketed log line, not "[PHP Modules]",
    # not a Haskell tuple list), and at least one "key": field exists.
    local t="${text#"${text%%[![:space:]]*}"}"
    [[ "$t" == '['* ]] || return 1
    t="${t#\[}"
    t="${t#"${t%%[![:space:]]*}"}"
    [[ "$t" == '{'* ]] || return 1
    [[ "$text" =~ \"[A-Za-z_][A-Za-z0-9_.-]*\"[[:space:]]*: ]] || return 1
    _STRATEGY_CONFIDENCE=88
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
