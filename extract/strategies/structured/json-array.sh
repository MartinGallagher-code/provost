#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: json-array
## Description: Top-level JSON array of objects — one record per element (az/gcloud/aws list, docker inspect); nested objects flattened with dotted keys
## Version: 1.1
## Priority: 9
## Sample: samples/json-array/basic.txt

# A top-level JSON ARRAY of objects is a list of records; parsing it as one
# blob (the `json` strategy's 0.field/1.field flatten) buries that. This
# parser emits one record per array element — the natural tidy shape for
# every `<cli> list --format=json` and `docker inspect` style output.
#
# v1.1 — nested values are FLATTENED, not skipped. `docker network inspect`
# keeps its real data inside nested objects (`IPAM.Config[0].Subnet`, the
# `Options` and `Labels` maps), and dropping them lost most of the record —
# the reviewer's "nope". A nested OBJECT's scalars emit with a dotted prefix
# (`Options.com.docker.network.driver.mtu 1500`); a nested ARRAY of objects
# emits with an element index in the path (`IPAM.Config.1.Subnet`); arrays
# of scalars emit indexed (`Tags.1 web`).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Strip a UTF-8 BOM (EF BB BF) if present — common in JSON exported from
    # Windows tools — so it doesn't hide the leading '[' from the check below.
    local bom; bom=$(printf '\xef\xbb\xbf')
    text="${text#"$bom"}"
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
            gsub(/[\t\r\n]/," ",v)   # a value keeps its inner spaces
            return v
        }
        # Emit "key": value pairs of the object (obj includes its outer
        # braces) under entry number e, key path prefix pfx. Nested objects
        # recurse with a dotted prefix; nested arrays recurse per element
        # with a 1-based index in the path; scalars print.
        function emit(obj, e, pfx,   n,i,c,key,val,vc,end) {
            n=length(obj); i=2   # skip opening {
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
                    if (c=="{") {                 # nested object: recurse
                        end=findmatch(obj,i)
                        emit(substr(obj,i,end-i+1), e, pfx key ".")
                        i=end+1; continue
                    }
                    if (c=="[") {                 # nested array: recurse per element
                        end=findmatch(obj,i)
                        emitarr(substr(obj,i,end-i+1), e, pfx key ".")
                        i=end+1; continue
                    }
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
                    if (key != "") print "entry" e "." pfx key " " clean(val)
                } else i++
            }
        }
        # Elements of a [...] value under key path pfx: objects recurse with
        # a 1-based index segment, scalars print indexed.
        function emitarr(arr, e, pfx,   n,i,c,idx,end,val,vc) {
            n=length(arr); i=2; idx=0
            while (i<=n) {
                c=substr(arr,i,1)
                if (c ~ /[ \t\r\n,]/) { i++; continue }
                if (c=="]") break
                idx++
                if (c=="{") {
                    end=findmatch(arr,i)
                    emit(substr(arr,i,end-i+1), e, pfx idx ".")
                    i=end+1; continue
                }
                if (c=="[") {
                    end=findmatch(arr,i)
                    emitarr(substr(arr,i,end-i+1), e, pfx idx ".")
                    i=end+1; continue
                }
                val=""
                if (c=="\"") { val="\""; i++
                    while (i<=n) { vc=substr(arr,i,1); val=val vc
                        if (vc=="\\") { i++; val=val substr(arr,i,1) }
                        else if (vc=="\"") { i++; break }
                        i++ }
                } else {
                    while (i<=n) { vc=substr(arr,i,1); if (vc=="," || vc=="]") break; val=val vc; i++ }
                }
                print "entry" e "." pfx idx " " clean(val)
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
                        emit(substr(s,i,end-i+1), e, "")
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
