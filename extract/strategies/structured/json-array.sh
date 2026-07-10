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
    # Full input as one record so we can scan across newlines — handles both
    # pretty-printed objects (one field per line) and compact one-object-per-
    # line arrays (`[{"a":1,"b":2},{...}]`, the shape rclone/shellcheck/most
    # `--format json` tools emit).
    printf '%s' "$1" | awk '
        # Index of the char closing the {...} or [...] opened at "start".
        function findmatch(s, start,   i,n,c,instr,esc,d) {
            n=length(s); d=0; instr=0; esc=0
            for (i=start; i<=n; i++) {
                c=substr(s,i,1)
                if (instr) { if (esc) esc=0; else if (c=="\\") esc=1; else if (c=="\"") instr=0; continue }
                if (c=="\"") { instr=1; continue }
                if (c=="{" || c=="[") d++
                else if (c=="}" || c=="]") { d--; if (d==0) return i }
            }
            return n
        }
        function clean(v) {
            gsub(/^[ \t\r\n]+/,"",v); gsub(/[ \t\r\n,]+$/,"",v)
            if (substr(v,1,1)=="\"") { v=substr(v,2); sub(/"$/,"",v) }
            gsub(/[ \t\r\n]+/,"_",v)
            return v
        }
        # Emit scalar "key": value pairs at the object top level (obj includes
        # its outer braces). Nested objects/arrays as values are skipped.
        function emit(obj, e,   n,i,c,instr,esc,key,val,ve,vc) {
            n=length(obj); instr=0; esc=0; i=2   # skip opening {
            while (i<=n) {
                c=substr(obj,i,1)
                if (c=="\"") {                    # a key
                    key=""; i++
                    while (i<=n) { c=substr(obj,i,1)
                        if (c=="\\") { i+=2; continue }
                        if (c=="\"") { i++; break }
                        key=key c; i++ }
                    while (i<=n && substr(obj,i,1) ~ /[ \t\r\n]/) i++
                    if (substr(obj,i,1) != ":") continue
                    i++
                    while (i<=n && substr(obj,i,1) ~ /[ \t\r\n]/) i++
                    c=substr(obj,i,1)
                    if (c=="{" || c=="[") { i=findmatch(obj,i)+1; continue }   # nested: skip
                    # scalar value: read to next top-level , or }
                    val=""
                    if (c=="\"") { val="\""; i++
                        while (i<=n) { vc=substr(obj,i,1); val=val vc
                            if (vc=="\\") { i++; val=val substr(obj,i,1) }
                            else if (vc=="\"") { i++; break }
                            i++ }
                    } else {
                        while (i<=n) { vc=substr(obj,i,1); if (vc=="," || vc=="}") break; val=val vc; i++ }
                    }
                    if (key != "") print "entry" e "." key " " clean(val)
                } else i++
            }
        }
        { buf = buf $0 "\n" }
        END {
            s=buf; n=length(s); instr=0; esc=0; ad=0; od=0; e=0; i=1
            while (i<=n) {
                c=substr(s,i,1)
                if (instr) { if (esc) esc=0; else if (c=="\\") esc=1; else if (c=="\"") instr=0; i++; continue }
                if (c=="\"") { instr=1; i++; continue }
                if (c=="[") { ad++; i++; continue }
                if (c=="]") { ad--; i++; continue }
                if (c=="{") {
                    if (ad==1 && od==0) {           # a top-level array element
                        end=findmatch(s,i); e++
                        emit(substr(s,i,end-i+1), e)
                        i=end+1; continue
                    }
                    od++; i++; continue
                }
                if (c=="}") { od--; i++; continue }
                i++
            }
            if (e>0) print "total_entries " e
        }
    '
}
