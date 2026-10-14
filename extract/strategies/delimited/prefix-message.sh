#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: prefix-message
## Description: Line-oriented diagnostics and logs — a typed prefix (file:line:col, timestamp, level, [thread], pid, logger, code, marker) then a free-text message; continuation lines (stack traces, carets, DETAIL:) attach to the record above
## Version: 1.0
## Priority: 45
## Confidence-Max: 84
## Sample: samples/prefix-message/basic.txt

# Compiler diagnostics and application logs share one shape: every record
# line opens with a short run of TYPED fields, then free text:
#
#   src/app.py:14:80: E501 line too long (97 > 79 characters)
#   main.c:6:5: error: 'y' undeclared (first use in this function)
#   Program.cs(42,17): warning CS0168: The variable 'ex' is declared but never used
#   2026-10-14 09:15:02,977 ERROR [pool-2-thread-3] c.a.sync.Supplier - Sync failed
#   2026/10/14 09:47:10 [error] 29#29: *1182 open() failed
#   INFO:app.db:Connected to postgres
#
# and the lines that do not open that way usually belong to the record above
# them (a Java / Python stack trace, gcc / rustc caret diagrams, PostgreSQL
# DETAIL: / STATEMENT: lines). Without a parser for this shape such inputs
# fell to text-lines (one column of whole lines) or were split at the wrong
# places (colon-fields cut timestamps at their colons, aligned-columns took the
# first log line as a header).
#
# GRAMMAR. A small lexer reads the typed fields off the start of each
# unindented line, left to right, until the next token is none of them:
#   T timestamp   ISO 8601 (+ zone abbreviation), 2026/10/14 10:00:00,
#                 14-Oct-2026 / 14 Oct 2026 10:00:00, ctime / BSD syslog,
#                 java.util.logging `Oct 14, 2026 1:00:00 PM`, a bare time
#                 (+ AM/PM); glog/klog `I1014 08:12:01.004512` is level + time
#   L level       TRACE DEBUG INFO NOTICE WARN(ING) ERROR FATAL CRITICAL SEVERE
#                 note hint help ... in any common spelling; a bare lowercase
#                 word only with a colon (`warning:`), after a file:line, or
#                 before an error code; single letters (I W E F D, telegraf
#                 `I!`) only after another field; rustc `error[E0308]:` carries
#                 its code; python `INFO:logger:msg` its logger; any ALL-CAPS
#                 `LABEL:` right after a timestamp / bracket / pid
#   O location    path:line[:col][:] and path(line[,col]): (msbuild / tsc);
#                 the path must name a file (`.`, `/`, `\`, or `Dockerfile`)
#   B [bracketed] named by what most of its cells hold: timestamp, level, pid,
#                 code, else `thread` (beside a logger) or `tag`
#   C code        E501, TS2322:, CS0168:, DL3008, SC2086 (after another field)
#   P pid         nginx `29#29:`, redis `1:M`, a bare number between the
#                 time / level and a further field (spring, mysql, glog)
#   H host + process[pid]: after a timestamp (journal short-iso), process[pid]:
#   G logger      `name - msg`, `name   : msg` (spring), python `LEVEL:name:`
#   M marker      one symbol opening the line: * > < + ! ~ ✔ ✖ ✓ ✗ ⚠ ...
# and lone `-`, `--`, `---`, `|`, `:` between fields are separators. The
# GRAMMAR is the longest field sequence shared by >= 80% of the lines that
# open with the most common first field. A line whose fields match it is a
# RECORD; one that matches at least half of it (an optional trailing field
# missing — spring's unparseable logger on one line) is a record with those
# cells empty. The rest of a record line is its `message`; a trailing `[...]`
# on most records (mypy / shellcheck / gcc `[-Wflag]` / eslint unix) becomes
# `code` (or `tag` when the prefix already had a code).
#
# CONTINUATION. A non-record line after a record is attached to it, in a
# `detail` column joined with `; ` (bracket-log's convention), when it is
# indented, or reads as a continuation: `at ...`, `... N more`, `Caused by:`,
# a Java / Python exception line, `Traceback (most recent call last):`, an
# ALL-CAPS `KEYWORD:` (PostgreSQL DETAIL: / HINT: / STATEMENT:), a source
# excerpt gutter `12 |` or a caret line. rustc / deno / codespan print the
# location under the headline (`  --> src/db.rs:31:20`): when a record has no
# location of its own, that first continuation line fills file/line/col.
# A title right above a record (gcc `main.c: In function 'main':`, go vet
# `# pkg`, pylint `***** Module x`) is the `context` of the records below it;
# a bare rule line (----) is layout. Any other line (a preamble, a summary
# such as `2 errors`) is a row of its own holding only `message` — nothing is
# dropped and nothing is welded into a neighbour.
#
# CONFIDENCE (see extract/README.md "Confidence rubric"). Evidence points per
# grammar field: a timestamp with a date, a bracketed timestamp or a
# file:line:col 2; a bare time, file:line, level, logger, host, code or
# bracketed level 1; pid / marker / tag 0.5. A location found under the
# headline, a trailing [code] on most diagnostics, and a stack-trace / caret
# continuation on most records add 1 each. Three points or more is a
# format-level grammar (ceiling 84, just under the strict grammar tier, so
# csv / quoted-fields / bracket-log's 85 keep their inputs); two points 80;
# less 72 (above aligned-columns' 69 and the catch-alls). The ceiling drops
# by a third of the share of non-blank lines the grammar does not explain
# (records, continuations and titles are explained, and so is a banner or a
# summary of <= 3 lines before the first / after the last record); below 70%
# explained, or with free lines over 40% of the rows, the detector declines.
# A BSD-syslog timestamp caps it at 79 so syslog (80) keeps its inputs. Every
# share threshold widens by the sample slack (_FR_SLACK) in the accepting
# direction.
#
# NOT A LOG. Declines: one weak field over messages of one word count (s3cmd
# ls, `aws s3 ls`: a date column over a size / name grid), messages that keep
# 2+-space column gaps (sar / mpstat / pidstat under a time column), a lone
# level column whose values never repeat (`Error: 0` / `Warning: 2` is a
# key/value block), one marker repeated (a `* item` list), a single
# [bracketed] field (bracket-log's), locations without line numbers.
#
# One awk program does detection and extraction (mawk-safe; no bash line
# loop), so the same code serves every input size.

_pm_awk () {
    awk -v MODE="$1" -v SLACK="${_FR_SLACK:-0}" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # level keyword: all-lower, ALL-UPPER or Capitalised spelling
    function islevel(w,    lw) {
        lw = tolower(w)
        if (!(lw in LEVELS)) return 0
        if (w == lw || w == toupper(w)) return 1
        return (substr(w, 2) == substr(lw, 2))
    }
    # length of the timestamp opening r (0 = none)
    function tslen(r,    n) {
        if (match(r, RE_ISO)) {
            n = RLENGTH
            if (match(substr(r, n + 1), RE_ZONE)) n += RLENGTH
            return n
        }
        if (match(r, RE_SLASH) || match(r, RE_DMY) || match(r, RE_TIME)) return RLENGTH
        if (substr(r, 1, 1) ~ /[A-Z]/ && (match(r, RE_CTIME) || match(r, RE_JUL))) return RLENGTH
        return 0
    }
    # r[n+1] ends a field: end of line or a blank
    function bound(r, n,    c) { c = substr(r, n + 1, 1); return (c == "" || c == " " || c == "\t") }
    # record one prefix field: type t, value v, extra x, consuming len bytes
    function put(t, v, x, len) {
        NL++; LT[NL] = t; LV[NL] = v; LX[NL] = x
        P += len
        while (substr(S, P, 1) == " " || substr(S, P, 1) == "\t") P++
        LP[NL] = P
    }
    # what a [bracketed] field holds
    function bclass(s,    w) {
        if (s ~ /^[0-9]+[.][0-9]+$/) return "ts"
        if (s ~ /^[0-9A-Z]/ && tslen(s) == length(s)) return "ts"
        w = s; sub(/:$/, "", w)
        if (w ~ /^[A-Za-z]+$/ && (islevel(w) || tolower(w) == "system")) return "lvl"
        if (s ~ /^[0-9]+$/ || s ~ /^pid [0-9]+/) return "pid"
        if (s ~ /^[A-Z][A-Z]*-?[0-9][0-9]/) return "code"
        return "tag"
    }
    function isfile(w) {
        if (w == "" || index(w, "://") || w !~ /[A-Za-z]/ || w ~ /^[0-9.]+$/) return 0
        if (w ~ /[.\/\\]/) return 1
        return (w ~ /^[A-Z][a-z]*file$/)
    }
    # split the typed prefix of S into LT/LV/LX/LP[1..NL]
    function lex(    r, n, w, c, k, inner, prev, glued, q, qa, tok, barepid) {
        NL = 0; P = 1; barepid = 0
        while (NL < 10) {
            r = substr(S, P)
            if (r == "") break
            prev = (NL > 0) ? LT[NL] : ""
            c = substr(r, 1, 1)
            match(r, /^[^ \t]+/); tok = substr(r, 1, RLENGTH)
            # [bracketed] field / <level>
            if (c == "[" || c == "<") {
                k = index(r, (c == "[") ? "]" : ">")
                if (k <= 2) break
                inner = trim(substr(r, 2, k - 2)); sub(/[ ,]+$/, "", inner)
                n = k
                if (substr(r, n + 1, 1) == ":") n++
                if (inner == "" || index(inner, c) || !bound(r, n)) break
                w = bclass(inner)
                if (c == "<" && w != "lvl") break
                put("B", inner, w, n)
                continue
            }
            if (c ~ /[0-9]/) {
                n = tslen(r)
                if (n > 0 && bound(r, n)) { put("T", substr(r, 1, n), "", n); continue }
                if (NL == 0 && match(r, /^[0-9]+:[A-Z]/) && bound(r, RLENGTH)) { put("P", substr(r, 1, RLENGTH), "", RLENGTH); continue }
                if (NL > 0 && match(tok, /^[0-9]+#[0-9]+:$/)) { put("P", substr(tok, 1, RLENGTH - 1), "", RLENGTH); continue }
                if (NL > 0 && (prev == "T" || prev == "L") && tok ~ /^[0-9]+$/) { put("P", tok, "", length(tok)); barepid = NL; continue }
            } else if (c ~ /[A-Za-z]/) {
                # glog / klog: Lmmdd hh:mm:ss.uuuuuu
                if (NL == 0 && c ~ /[IWEF]/ && match(r, /^[IWEF][01][0-9][0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]([.][0-9]+)?/) && bound(r, RLENGTH)) {
                    n = RLENGTH
                    NL++; LT[NL] = "L"; LV[NL] = c; LX[NL] = ""; LP[NL] = P + 1
                    put("T", substr(r, 2, n - 1), "", n)
                    continue
                }
                if (c ~ /[A-Z]/ && (n = tslen(r)) > 0 && bound(r, n)) { put("T", substr(r, 1, n), (r ~ RE_BSD) ? "bsd" : "", n); continue }
                # level word; also rustc `error[E0308]:` and gcc `fatal error:`
                match(r, /^[A-Za-z]+/); w = substr(r, 1, RLENGTH); n = RLENGTH
                if (n == 1) {
                    if (NL > 0 && w ~ /[IWEFDVTN]/) {
                        if (substr(r, 2, 1) == "!") n = 2
                        if (bound(r, n)) { put("L", w, "", n); continue }
                    }
                } else if (NL > 0 && (prev == "T" || prev == "B" || prev == "P") && w == toupper(w) && n >= 3 && substr(r, n + 1, 1) == ":" && bound(r, n + 1) && !islevel(w)) {
                    # an ALL-CAPS label in the level slot of a log prefix
                    # (`[2207] DETAIL:  …` beside `[2207] ERROR:  …`)
                    put("L", w, "", n + 1); continue
                } else if (islevel(w)) {
                    q = ""
                    if (tolower(w) == "fatal" && tolower(substr(r, n + 1, 6)) == " error") { w = substr(r, 1, n + 6); n += 6 }
                    if (substr(r, n + 1, 1) == "[") {
                        k = index(substr(r, n + 1), "]")
                        if (k > 2) { q = substr(r, n + 2, k - 2); n += k }
                    }
                    glued = 0
                    if (substr(r, n + 1, 1) == ":") {
                        n++
                        if (!bound(r, n) && substr(r, n + 1, 1) ~ /[A-Za-z_]/) glued = 1
                    } else if (substr(r, n + 1, 1) == "!") n++
                    # a bare lowercase word (`trace id …`, `note that …`) is prose
                    # unless it follows a file:line or precedes an error code
                    if ((glued || bound(r, n)) && (q != "" || substr(r, n, 1) ~ /[:!]/ || w != tolower(w) || prev == "O" || substr(r, n + 1) ~ RE_CODEAFTER)) {
                        put("L", w, q, n)
                        if (glued) LP[NL] = P
                        # python logging: LEVEL:logger:message
                        if (glued && match(substr(S, P), /^[A-Za-z_][A-Za-z0-9_.]*:/)) put("G", substr(S, P, RLENGTH - 1), "", RLENGTH)
                        continue
                    }
                }
            } else if (NL == 0 && match(r, RE_MARK) && bound(r, RLENGTH)) {
                # single-symbol line marker (curl -v, CI step lists)
                put("M", substr(r, 1, RLENGTH), "", RLENGTH); continue
            }
            # file(line,col): — msbuild / dotnet / tsc
            if (index(tok, "(") && match(r, /^([A-Za-z]:)?[^ \t():]+[(][0-9]+(,[0-9]+)*[)]:?/) && bound(r, RLENGTH)) {
                n = RLENGTH; w = substr(r, 1, n); sub(/:$/, "", w)
                k = index(w, "("); inner = substr(w, k + 1); sub(/[)]$/, "", inner)
                if (substr(w, 1, k - 1) ~ /[.\/\\]/) {
                    split(inner, qa, ",")
                    put("O", substr(w, 1, k - 1), qa[1] SUBSEP ((2 in qa) ? qa[2] : ""), n)
                    continue
                }
            }
            # file:line[:col][:]
            if (index(tok, ":") && match(r, RE_LOC) && bound(r, RLENGTH)) {
                n = RLENGTH; w = substr(r, 1, n); sub(/[]:]$/, "", w)
                if (match(w, /:[0-9]+(:[0-9]+)?$/)) {
                    inner = substr(w, RSTART + 1); w = substr(w, 1, RSTART - 1)
                    if (isfile(w)) {
                        k = index(inner, ":")
                        if (k) put("O", w, substr(inner, 1, k - 1) SUBSEP substr(inner, k + 1), n)
                        else put("O", w, inner SUBSEP "", n)
                        continue
                    }
                }
            }
            if (NL == 0) break
            # error code: E402  TS2322:  CS0168:  DL3008  SC2086
            if (c ~ /[A-Z]/ && tok ~ /^[A-Z][A-Z]?[A-Z]?[A-Z]?[A-Z]?-?[0-9][0-9][0-9]*:?$/) {
                w = tok; sub(/:$/, "", w)
                put("C", w, "", length(tok)); continue
            }
            if (c ~ /[A-Za-z]/) {
                # host process[pid]: right after a timestamp (journal short-iso)
                if (prev == "T" && match(r, /^[A-Za-z0-9][A-Za-z0-9_.-]* [A-Za-z0-9_.\/@()-]+(\[[0-9]+\])?:/) && bound(r, RLENGTH)) {
                    n = RLENGTH; w = substr(r, 1, n - 1); k = index(w, " ")
                    inner = substr(w, k + 1); w = substr(w, 1, k - 1)
                    q = ""
                    if (match(inner, /\[[0-9]+\]$/)) { q = substr(inner, RSTART + 1, RLENGTH - 2); inner = substr(inner, 1, RSTART - 1) }
                    put("H", w, inner SUBSEP q, n); continue
                }
                # process[pid]:
                if (match(tok, /^[A-Za-z][A-Za-z0-9_.\/@-]*\[[0-9]+\]:$/)) {
                    w = substr(tok, 1, RLENGTH - 1); k = index(w, "[")
                    q = substr(w, k + 1); sub(/\]$/, "", q)
                    put("H", "", substr(w, 1, k - 1) SUBSEP q, RLENGTH); continue
                }
            }
            # logger: name - message / name   : message
            if (c ~ /[A-Za-z_$]/ && match(r, /^[A-Za-z_$][A-Za-z0-9_$.]*( +- | +: )/)) {
                w = substr(r, 1, RLENGTH); sub(/ +[-:] $/, "", w)
                put("G", w, "", RLENGTH); continue
            }
            # field separators: - -- --- | : (not the last thing on the line)
            if ((tok == "-" || tok == "--" || tok == "---" || tok == "|" || tok == ":" || tok == "::") && length(tok) < length(r)) {
                P += length(tok)
                while (substr(S, P, 1) == " " || substr(S, P, 1) == "\t") P++
                LP[NL] = P
                continue
            }
            break
        }
        # a bare number is only an id when another field follows it (a size
        # column after a date is data)
        if (barepid && barepid == NL) NL--
        return NL
    }
    # a line that continues the record above it: 2 = a shape only a
    # continuation has, 1 = merely indented, 0 = neither
    function contshape(s) {
        if (s ~ /^[ \t]/) { sub(/^[ \t]+/, "", s); return (contshape(s) == 2 || s ~ /^(at |File "|from |--> |= )/) ? 2 : 1 }
        if (s ~ /^(Caused by|Suppressed|Traceback [(]most recent call last[)]|During handling of the above exception|The above exception was)/) return 2
        if (s ~ /^at [A-Za-z_$<]/ || s ~ /^[.][.][.] [0-9]+ more/) return 2
        if (s ~ /^([a-z_$][A-Za-z0-9_$]*[.])+[A-Z][A-Za-z0-9_$]*(: |:$|$)/) return 2
        if (s ~ /^[A-Z][A-Za-z0-9_]*(Error|Exception|Warning|Exit|Interrupt|Iteration)(: |:$|$)/) return 2
        if (s ~ /^[A-Z][A-Z]+( [0-9]+)?:( |$)/) return 2
        if (s ~ /^[0-9]* *[|]/ || s ~ /^[~^]/ || s ~ /^--> /) return 2
        return 0
    }
    # a title line over the records below it
    function headshape(s) {
        if (s ~ /^[ \t]/) return 0
        s = trim(s)
        if (s ~ /^# [^ ]/) return 1
        if (s ~ /^([*][*][*]+|===+|---+|###+) *[^ *=#-]/) return 1
        return (s ~ /:$/ && length(s) > 1 && s !~ /^[A-Z][A-Z]+:$/)
    }
    # line i is a record: its prefix is the grammar, or (a field or two short)
    # agrees with at least half of it -> MM = fields matched
    function isrec_(i,    sg, m) {
        if (!(i in SIG)) return 0
        sg = SIG[i]
        if (substr(sg, 1, K) == best) { MM = K; return 1 }
        for (m = 0; m < K && m < length(sg) && substr(sg, m + 1, 1) == substr(best, m + 1, 1); m++) ;
        if (m == 0 || m * 2 < K) return 0
        MM = m; return 1
    }
    # GV/GX/GE[1..n] = value / extra / end offset of each field of line i
    function unpack(i,    n, j, a, b) {
        n = split(PK[i], a, "\002")
        for (j = 1; j <= n; j++) { split(a[j], b, "\001"); GV[j] = b[1]; GX[j] = b[2]; GE[j] = b[3] + 0 }
        return n
    }
    function addcol(name, j, how) { nc++; CN[nc] = name; CJ[nc] = j; CH[nc] = how }
    function cell(r, c,    i, j, how, v, q) {
        j = CJ[c]; how = CH[c]; v = ""
        if (how == "m") v = MSG
        else if (how == "t") v = TV
        else if (how == "d") v = (r in DET) ? DET[r] : ""
        else if (how == "c") v = (r in CTX) ? CTX[r] : ""
        else if (how == "af") v = (r in AF) ? AF[r] : ""
        else if (how == "al") v = (r in AF) ? AL[r] : ""
        else if (how == "ac") v = (r in AF) ? AC[r] : ""
        else if (REC[r] > 0 && j <= RM[r]) {
            if (how == "v") v = GV[j]
            else if (how == "x") v = GX[j]
            else { split(GX[j], q, SUBSEP); v = (how == "x1") ? q[1] : q[2] }
        }
        gsub(/\t/, " ", v)
        return trim(v)
    }
    # MSG / TV for record r (record lines must be unpacked first)
    function message(r,    i) {
        i = REC[r]
        if (i > 0) MSG = substr(LINE[i], GE[RM[r]]); else MSG = LINE[-i]
        MSG = trim(MSG); gsub(/\t/, " ", MSG)
        TV = ""
        if (trail != "" && i > 0 && match(MSG, / \[[^]\[]+\]$/)) {
            TV = substr(MSG, RSTART + 2, RLENGTH - 3); MSG = trim(substr(MSG, 1, RSTART - 1))
        }
    }
    BEGIN {
        split("trace debug dbug dbg info inf information informational notice note warn warning wrn err error eror fatal crit critical alert emerg emergency panic severe fine finer finest config verbose log hint help remark", lv, " ")
        for (i in lv) LEVELS[lv[i]] = 1
        MON = "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"
        HMS = "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]([.,][0-9]+)?"
        RE_ISO = "^[0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9][T ][0-2][0-9]:[0-5][0-9](:[0-5][0-9])?([.,][0-9]+)?(Z|[+-][0-9][0-9](:?[0-9][0-9])?)?"
        RE_ZONE = "^ (UTC|GMT|CET|CEST|EET|EEST|WET|WEST|BST|IST|EST|EDT|CST|CDT|MST|MDT|PST|PDT|AEST|AEDT|JST|KST|HKT|SGT|MSK|NZST|NZDT)"
        RE_SLASH = "^[0-9][0-9][0-9][0-9]/[01][0-9]/[0-3][0-9][ T]" HMS
        RE_DMY = "^[0-3]?[0-9][-/ ]" MON "[-/ ][0-9][0-9][0-9][0-9][ :]" HMS "( [+-][0-9][0-9][0-9][0-9])?"
        RE_CTIME = "^((Mon|Tue|Wed|Thu|Fri|Sat|Sun) )?" MON " [ 0-3][0-9] " HMS "( [0-9][0-9][0-9][0-9])?"
        RE_BSD = "^" MON " [ 0-3][0-9] [0-2][0-9]:"
        RE_JUL = "^" MON " [0-3]?[0-9], [0-9][0-9][0-9][0-9] [01]?[0-9]:[0-5][0-9]:[0-5][0-9] (AM|PM)"
        RE_TIME = "^" HMS "( [AP]M)?"
        RE_MARK = "^([*><+!~]|✖|✔|✓|✗|✘|⚠|ℹ|⧗|×|➜|❯|→)"
        RE_CODEAFTER = "^ +[A-Z][A-Z]?[A-Z]?[A-Z]?[A-Z]?-?[0-9][0-9][0-9]*:? "
        RE_LOC = "^([A-Za-z]:)?[^ \t:()<>\"" sprintf("%c", 39) "=,]+:[0-9]+(:[0-9]+)?[]:]?"
    }
    {
        sub(/\r$/, "")
        N++; LINE[N] = $0
        if ($0 !~ /[^ \t]/) { BL[N] = 1; next }
        NB++
        if ($0 ~ /^[ \t]/) next
        S = $0
        k = lex()
        if (k == 0) next
        sig = ""; pk = ""
        for (j = 1; j <= k; j++) {
            sig = sig LT[j]
            pk = pk (j > 1 ? "\002" : "") LV[j] "\001" LX[j] "\001" LP[j]
            PC[sig]++
        }
        FC[LT[1]]++
        SIG[N] = sig; PK[N] = pk
    }
    END {
        slack = SLACK + 0
        # the record grammar: the longest typed prefix shared by >= 80% of the
        # lines that open with the most common first field
        top = 0
        for (s in FC) if (FC[s] > top) top = FC[s]
        best = ""; bc = 0
        for (s in PC) {
            if (PC[s] < 2 || PC[s] * 100 < top * 80) continue
            if (length(s) > length(best) || (length(s) == length(best) && (PC[s] > bc || (PC[s] == bc && s < best)))) { best = s; bc = PC[s] }
        }
        if (best == "") { if (MODE == "detect") print "0 no-grammar"; exit }
        K = length(best); hasO = (index(best, "O") > 0)
        # the role of every line: record, title, rule, continuation, free line
        R = 0; C = 0; H = 0; F = 0; ctx = ""; cur = 0; isrec = 0; nal = 0; nstrong = 0; lead = 0; ftail = 0
        for (i = 1; i <= N; i++) {
            if (BL[i]) continue
            if (isrec_(i)) {
                R++; NR_++; cur = NR_; isrec = 1; REC[cur] = i; RM[cur] = MM; ftail = 0
                if (ctx != "") CTX[cur] = ctx
                continue
            }
            # a bare rule (----- / =====) is layout, not data
            if (LINE[i] ~ /^[ \t]*[-=*_#~][-=*_#~][-=*_#~]+[ \t]*$/) { H++; continue }
            # a title over the records that follow it (gcc `x.c: In function
            # main:`, go vet `# pkg`) is their context
            if (headshape(LINE[i])) {
                for (j = i + 1; j <= N && BL[j]; j++) ;
                if (j <= N && isrec_(j)) {
                    H++; ctx = trim(LINE[i]); sub(/:$/, "", ctx)
                    sub(/^(# |[*][*][*]+ *|===+ *|---+ *|###+ *)/, "", ctx); sub(/ *([*][*][*]+|===+|---+|###+)$/, "", ctx)
                    continue
                }
            }
            if (cur > 0 && (cs = contshape(LINE[i]))) {
                if (isrec) { C++; if (cs == 2 && !(cur in STRONG)) { STRONG[cur] = 1; nstrong++ } } else { F++; if (R == 0) lead++; else ftail++ }
                # rustc / deno / codespan put the location under the headline
                if (isrec && !hasO && !(cur in DET) && !(cur in AF) && match(LINE[i], /^[ \t]*(-->|┌─|╭─\[?|,-\[) *[^ :\[\]]+:[0-9]+(:[0-9]+)?/)) {
                    v = substr(LINE[i], RSTART, RLENGTH); sub(/^[ \t]*(-->|┌─|╭─\[?|,-\[) */, "", v)
                    k = split(v, q, ":"); AF[cur] = q[1]; AL[cur] = q[2]; AC[cur] = (k > 2) ? q[3] : ""; nal++
                    continue
                }
                v = trim(LINE[i]); gsub(/\t/, " ", v)
                if (cur in DET) DET[cur] = DET[cur] "; " v; else DET[cur] = v
                continue
            }
            F++; NR_++; cur = NR_; isrec = 0; REC[cur] = -i
            if (R == 0) lead++; else ftail++
        }
        # a short banner before the first record and a short summary after the
        # last one (`2 errors`, `Found 3 problems`) are part of the shape
        if (lead > 3) lead = 0
        if (ftail > 3) ftail = 0
        # evidence per grammar field
        pts = 0; bsd = 0
        for (j = 1; j <= K; j++) { t = substr(best, j, 1); NDT[j] = 0; NLN[j] = 0; NCO[j] = 0 }
        delete MV; nm = 0; rep = 0; ntc = 0; ng = 0; ng1 = 0; wm = 0; wmn = 0; lcode = 0
        for (r = 1; r <= NR_; r++) {
            if (REC[r] <= 0) continue
            i = REC[r]; unpack(i)
            for (j = 1; j <= RM[r]; j++) {
                t = substr(best, j, 1)
                if (t == "B") BCN[j, GX[j]]++
                else if (t == "T") { if (GV[j] ~ /[-\/]|[0-9][0-9][0-9][0-9]|[A-Z][a-z][a-z] /) NDT[j]++; if (GX[j] == "bsd") bsd = 1 }
                else if (t == "O") { split(GX[j], q, SUBSEP); if (q[1] != "") NLN[j]++; if (q[2] != "") NCO[j]++ }
                else if (t == "L" && GX[j] != "") lcode = 1
            }
            v = tolower(GV[1]); if (v in MV) rep = 1; else { MV[v] = 1; nm++ }
            message(r)
            if (MSG ~ / \[[^]\[]+\]$/) ntc++
            if (MSG ~ /[^ ]   *[^ ].*[^ ]   *[^ ]/) ng++
            if (MSG ~ /[^ ]   *[^ ]/) ng1++
            nw = split(MSG, q, /[ \t]+/); WC[nw]++; if (WC[nw] > wm) { wm = WC[nw]; wmn = nw }
        }
        anchor = 0
        for (j = 1; j <= K; j++) {
            t = substr(best, j, 1)
            if (t == "B") {
                # a bracket column is named by what most of its cells hold
                bn = "tag"; bm = 0
                split("ts lvl pid code tag", BCL, " ")
                for (b = 1; b <= 5; b++) if (BCN[j, BCL[b]] > bm) { bn = BCL[b]; bm = BCN[j, BCL[b]] }
                BK[j] = bn
                if (bn == "ts") { pts += 2; anchor = 1 } else if (bn == "lvl") { pts += 1; anchor = 1 } else if (bn == "code") pts += 1; else pts += 0.5
            } else if (t == "T") { pts += (NDT[j] * 2 >= R) ? 2 : 1; anchor = 1 }
            else if (t == "O") {
                if (NLN[j] * 2 < R) { if (MODE == "detect") print "0 no-line-numbers"; exit }
                pts += (NCO[j] * 2 >= R) ? 2 : 1; anchor = 1
            }
            else if (t == "L" || t == "H" || t == "G") { pts += 1; anchor = 1 }
            else if (t == "C") pts += 1
            else pts += 0.5
        }
        if (nal * 2 >= R) pts += 1
        # most records carrying a trailing [code], or a continuation only a
        # diagnostic / stack trace has (carets, `at ...`), confirm the records
        if (ntc * 2 >= R && (hasO || nal * 2 >= R)) pts += 1
        if (nstrong * 2 >= R) pts += 1
        if (best == "B") anchor = 0
        # a marker column needs two or more distinct markers (a `* item` list is
        # one bullet repeated)
        if (best == "M" && nm >= 2) anchor = 1
        if (!anchor) { if (MODE == "detect") print "0 no-anchor"; exit }
        # a lone level column must repeat a value (distinct `Error: 0` /
        # `Warning: 2` labels are a key/value block)
        if ((best == "L" || best == "B") && !rep) { if (MODE == "detect") print "0 no-repeat"; exit }
        # one weak field over messages of one word count is a table, and so are
        # messages that keep 2+-space column gaps (sar / mpstat under a time)
        # (a reason to decline widens by the sample slack, see extract/README.md)
        if (pts <= 2 && R >= 3 && wmn >= 2 && wm * 100 >= R * (80 + slack)) { if (MODE == "detect") print "0 grid"; exit }
        if (ng * 100 >= R * (60 + slack) || (pts <= 2 && ng1 * 100 >= R * (50 + slack))) { if (MODE == "detect") print "0 column-gaps"; exit }
        share = int((R + C + H + lead + ftail) * 100 / NB)
        rshare = int(R * 100 / (R + F - lead - ftail))
        if (MODE == "detect") {
            if (share < 70 - slack || rshare < 60 - slack) { print "0 share " share " " rshare; exit }
            ceil_ = (pts >= 3) ? 84 : ((pts >= 2) ? 80 : 72)
            if (bsd && ceil_ > 79) ceil_ = 79
            conf = ceil_ - int((100 - share) / 3)
            if (conf < 56) conf = 56
            print conf, best, "records=" R, "continued=" C, "titles=" H, "free=" F
            exit
        }
        # ---- extract: one row per record (free lines are rows of their own)
        hascode = (index(best, "C") > 0) || lcode
        for (j = 1; j <= K; j++) if (substr(best, j, 1) == "B" && BK[j] == "code") hascode = 1
        hasloc = hasO || nal > 0
        trail = (ntc * 2 >= R) ? ((hascode || !hasloc) ? "tag" : "code") : ""
        nc = 0
        for (j = 1; j <= K; j++) {
            t = substr(best, j, 1)
            if (t == "T") addcol("timestamp", j, "v")
            else if (t == "L") { addcol(hasloc ? "severity" : "level", j, "v"); addcol("code", j, "x") }
            else if (t == "O") { addcol("file", j, "v"); addcol("line", j, "x1"); addcol("col", j, "x2") }
            else if (t == "C") addcol("code", j, "v")
            else if (t == "P") addcol("pid", j, "v")
            else if (t == "H") { addcol("host", j, "v"); addcol("process", j, "x1"); addcol("pid", j, "x2") }
            else if (t == "G") addcol("logger", j, "v")
            else if (t == "M") addcol("marker", j, "v")
            else if (BK[j] == "ts") addcol("timestamp", j, "v")
            else if (BK[j] == "lvl") addcol(hasloc ? "severity" : "level", j, "v")
            else if (BK[j] == "pid") addcol("pid", j, "v")
            else if (BK[j] == "code") addcol("code", j, "v")
            else addcol(index(best, "G") ? "thread" : "tag", j, "v")
        }
        if (nal > 0) { addcol("file", 0, "af"); addcol("line", 0, "al"); addcol("col", 0, "ac") }
        addcol("message", 0, "m")
        if (trail != "") addcol(trail, 0, "t")
        addcol("detail", 0, "d")
        addcol("context", 0, "c")
        # drop the columns that are empty on every row
        for (r = 1; r <= NR_; r++) {
            if (REC[r] > 0) unpack(REC[r])
            message(r)
            for (c = 1; c <= nc; c++) if (!(c in USED) && cell(r, c) != "") USED[c] = 1
        }
        # a repeated name gets a 2, 3, ... suffix
        for (c = 1; c <= nc; c++) {
            if (!(c in USED)) continue
            b = CN[c]; k = 1; v = b
            while (v in CUSED) { k++; v = b k }
            CUSED[v] = 1; CN[c] = v
        }
        for (r = 1; r <= NR_; r++) {
            if (REC[r] > 0) unpack(REC[r])
            message(r)
            for (c = 1; c <= nc; c++) if (c in USED) printf "entry%d.%s %s\n", r, CN[c], cell(r, c)
        }
        printf "total_entries %d\n", NR_
    }
'
}

strategy_detect () {
    local text="$1" out
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON=""
    out="$(_pm_awk detect <<< "$text")" || return 1
    [[ "$out" =~ ^([0-9]+)\ (.*)$ ]] || return 1
    [[ "${BASH_REMATCH[1]}" -gt 0 ]] || return 1
    _STRATEGY_CONFIDENCE="${BASH_REMATCH[1]}"
    _STRATEGY_CONFIDENCE_REASON="prefix grammar ${BASH_REMATCH[2]}"
    return 0
}

strategy_extract () {
    _pm_awk extract <<< "$1"
}
