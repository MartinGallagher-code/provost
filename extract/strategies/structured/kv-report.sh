#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: kv-report
## Description: Multi-section key/value reports — `key: value` lines, bare `Label:` lists, titled sections, wrapped values — as one lossless key/value table (the engine's coverage RESCUE parser)
## Version: 1.0
## Priority: 98
## Confidence-Max: 70
## Sample: samples/kv-report/basic.txt

# Environment and diagnostic dumps mix scalar `key: value` lines with LIST
# SECTIONS — a bare `Label:` over indented or bulleted items — and titled
# blocks, in one report:
#
#   Name: idna                         RubyGems-style:  Env:
#   Version: 3.6                                          - VERSION: 3.3.5
#   Files:                                                - PATHS:
#     idna/__init__.py                                       - /var/lib/gems
#     idna/codec.py                                          - /root/.gem
#
# A parser that recognises one part (the scalar lines, a banner, the first
# block) claims the whole input and drops the rest without a trace. This one
# keeps EVERY line, as one long key/value table — one row per scalar, one row
# per list item (the label repeated as its key), the enclosing title / label
# path in a `section` column, a `block` index when blank-separated blocks
# repeat their keys (one record per block):
#
#   section   key      value
#             Name     idna
#             Files    idna/__init__.py
#   Env       PATHS    /var/lib/gems
#
# Line grammar (indent = leading whitespace, a tab to the next multiple of 8,
# tree glyphs `│ ├ └ ─` counting as blanks; a leading `- ` / `* ` / `+ ` /
# `• ` bullet is stripped and remembered):
#   KV      `key: value` (the first colon followed by a blank) or `key = value`
#           (spaces around `=`); a key is 1-60 chars, holds a letter, at most
#           8 words, balanced brackets, no `://`, no clock time (a log line is
#           not a label) and no inner run of 2+ blanks (a table row is not);
#   HEADER  a KV with an empty value: `Label:`;
#   TITLE   a decorated line (`**** GPU usage ****`, `=== Foo ===`) or a line
#           underlined by a rule (`installed toolchains` / `-----`): it names
#           the section of everything below, up to the next title;
#   rules, blank lines and `#` / `;` comment lines carry no data (the
#           coverage measure skips them too); anything else is TEXT.
# Structure:
#   - a HEADER opens a list: deeper (or bulleted at its own indent) TEXT lines
#     are its items, `key = header`; deeper KV lines are fields of a section
#     named by it. A header whose very next line is unbulleted TEXT at its own
#     indent keeps a FLAT list (apt-style) until a blank line or the next KV.
#     A header with nothing under it is a key with an empty value;
#   - a KV is a section for the deeper KV lines right below it (docker's
#     `Containers: 12` over `Running: 6`) — not across a blank line, and not
#     in a RIGHT-ALIGNED listing (most keys sharing one colon column at
#     different indents: `   Raid Level : raid5` / `  Raid Devices : 4` are
#     siblings). Deeper TEXT lines right below a KV CONTINUE its value: they
#     are rows of their own (the key repeated) when they are short items — a
#     path, URL or name list — and are folded into the value with a space when
#     a piece ends in `,` (a wrapped comma list), a line is over 60 bytes
#     (wrapped prose) or the value is a block-scalar `|` / `>`; TEXT at the
#     KV's own indent folds only when it carries on a comma list;
#   - other TEXT is a section TITLE when it could name one (60 bytes or less,
#     no column gaps) and the next line is deeper, or when it opens a block
#     (short, no colon) over lines at its own indent — up to the next blank;
#     else it is a row with the line as its value (and no key).
# Output: a report that is ONE record (every row keyed, no key repeated) is
# one wide row — a column per key, named `section.key` — like the other
# single-record kv parsers; anything else is the long table above.
#
# RESCUE ONLY. A KV report is too common a shape to compete in the ordinary
# ranking, where it would take inputs from more specific parsers. The engine
# runs this strategy only as the COVERAGE RESCUE (lib/_discovery.sh, see
# "COVERAGE HOLD"): when the winning candidate's line coverage is low it is
# held, and this parse replaces it only if it covers materially more. So it
# detects only while the engine has set _FR_RESCUE=1, or when pinned with
# `--strategy kv-report`.

_KVR_AWK='
function indent_of(s,   i, c, w, n) {
    w = 0; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == " ") w++
        else if (c == "\t") w = w - w % 8 + 8
        else break
    }
    return w
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function okkey(k,   w, t) {
    if (k == "" || length(k) > 60 || k !~ /[A-Za-z]/) return 0
    if (index(k, "://") || k ~ /[ \t][ \t]/) return 0
    # a clock time inside the "key" is a log line, not a label
    if (k ~ /[0-9]:[0-9]/) return 0
    # brackets must balance: `Benchmark, Version 2.1 (Language: C)` is prose
    t = k; if (gsub(/\(/, "", t) != gsub(/\)/, "", t)) return 0
    t = k; if (gsub(/\[/, "", t) != gsub(/\]/, "", t)) return 0
    t = k; w = gsub(/[ \t]+/, " ", t)
    return (w < 8)
}
# a line that can NAME a section: short, no column gaps (a table row is not)
function titlelike(t) { return (length(t) <= 60 && t !~ /[ \t][ \t]/) }
# classify line i into K / H / O (text) / T (title) / R (rule) / C (comment)
# / B (blank); fills ind[], bul[], kk[], vv[], tx[]
function classify(i, line,   b, t, p, k, v) {
    sub(/[ \t\r]+$/, "", line)
    # tree-drawing glyphs (U+2500 U+2502 U+2514 U+251C U+252C U+253C) are
    # indentation, one column each
    if (index(line, "\342\224")) gsub(/\342\224\224|\342\224\200|\342\224\234|\342\224\202|\342\224\254|\342\224\274/, " ", line)
    if (line == "") { kind[i] = "B"; return }
    ind[i] = indent_of(line)
    b = line; sub(/^[ \t]+/, "", b)
    t = b; gsub(/[ \t|+]/, "", t)
    if (length(t) >= 3 && t ~ /^[-=_~*]+$/) { kind[i] = "R"; return }
    if (b ~ /^[*=#~-][*=#~-]+[ \t]+/ && b ~ /[ \t][*=#~-][*=#~-]+$/) {
        t = b; sub(/^[*=#~-]+[ \t]+/, "", t); sub(/[ \t]+[*=#~-]+$/, "", t)
        if (t ~ /[A-Za-z0-9]/) { kind[i] = "T"; tx[i] = trim(t); return }
    }
    if (b ~ /^[#;]/) { kind[i] = "C"; return }
    bul[i] = 0
    if (b ~ /^[-*+][ \t]+[^ \t]/) { bul[i] = 1; sub(/^[-*+][ \t]+/, "", b) }
    else if (substr(b, 1, 4) == "\342\200\242 ") { bul[i] = 1; b = substr(b, 5); sub(/^[ \t]+/, "", b) }
    tx[i] = b
    p = match(b, /:([ \t]|$)/)
    if (p > 1) {
        k = trim(substr(b, 1, p - 1)); v = trim(substr(b, p + 1))
        if (okkey(k)) { kk[i] = k; vv[i] = v; kind[i] = (v == "" ? "H" : "K"); cc[i] = length(line) - length(b) + p; return }
    }
    p = match(b, /[ \t]=[ \t]/)
    if (p > 1 && substr(b, p + 2, 1) != "=") {
        k = trim(substr(b, 1, p)); v = trim(substr(b, p + 2))
        if (okkey(k) && k ~ /^[A-Za-z_]/) { kk[i] = k; vv[i] = v; kind[i] = (v == "" ? "H" : "K"); cc[i] = length(line) - length(b) + p + 1; return }
    }
    kind[i] = "O"
}
function path(m,   s, j) {
    s = banner
    if (btitle != "") s = s (s == "" ? "" : " > ") btitle
    for (j = 1; j <= m; j++) s = s (s == "" ? "" : " > ") sname[j]
    return s
}
function emit(sec, k, v) {
    nr++; rsec[nr] = sec; rkey[nr] = k; rval[nr] = v; rblk[nr] = blk; brows++
    if (sec != "") anysec = 1
    if (k != "") {
        if (((sec, k) in keyblk) && keyblk[sec, k] != blk) rep = 1
        keyblk[sec, k] = blk
    }
    return nr
}
# end of a KV continuation run: a LIST (rows of their own, the key repeated)
# when its lines are short items, else WRAPPED text folded into the value — a
# piece ending in `,` (a wrapped comma list) or a line over 60 bytes (wrapped
# prose) means wrapped
function flushcont(   j, wrap) {
    if (!cn) return
    # (a YAML-style block scalar `key: |` / `key: >` is one value too)
    wrap = (rval[cr] ~ /,$/ || rval[cr] ~ /^[|>][-+]?[0-9]?$/)
    for (j = 1; j <= cn && !wrap; j++) if (cl[j] ~ /,$/ || length(cl[j]) > 60) wrap = 1
    if (!wrap) { for (j = 1; j <= cn; j++) emit(rsec[cr], rkey[cr], cl[j]) }
    else { for (j = 1; j <= cn; j++) rval[cr] = rval[cr] " " cl[j] }
    cn = 0
}
# next line index after i that carries data (skips C/R), or 0 at a blank /
# end — or, with overblank, past blank lines too
function nextdata(i, overblank,   j) {
    for (j = i + 1; j <= n; j++) {
        if (kind[j] == "C" || kind[j] == "R") continue
        if (kind[j] == "B") { if (overblank) continue; return 0 }
        return j
    }
    return 0
}
{ n++; raw[n] = $0 }
END {
    for (i = 1; i <= n; i++) classify(i, raw[i])
    # a TEXT line underlined by a rule (no blank between) is a title
    for (i = 1; i < n; i++)
        if (kind[i] == "O" && !bul[i] && kind[i + 1] == "R") kind[i] = "T"
    if (ENVIRON["_KVR_MODE"] == "detect") {
        for (i = 1; i <= n; i++) {
            if (kind[i] == "K") nk++
            else if (kind[i] == "H") nh++
            else if (kind[i] == "O") no++
        }
        tot = nk + nh + no
        # a kv report: several key lines, and they are a real share of it
        ok = (nk >= 2 && nk + nh >= 3 && (nk + nh) * 100 >= tot * 30)
        print (ok ? "yes" : "no")
        exit
    }
    # RIGHT-ALIGNED keys (`     Raid Level : raid5` over `   Raid Devices : 4`):
    # when most key lines share one colon column at different indents, a
    # deeper key is a sibling, never a child of the key above it
    for (i = 1; i <= n; i++) if (kind[i] == "K" || kind[i] == "H") {
        nkh++; ccn[cc[i]]++; if (!((cc[i], ind[i]) in cci)) { cci[cc[i], ind[i]] = 1; cind_n[cc[i]]++ }
    }
    for (c in ccn) if (ccn[c] > best) { best = ccn[c]; bestc = c }
    ralign = (best >= 3 && best * 2 >= nkh && cind_n[bestc] >= 2)
    nsec = 0; banner = ""; blk = 1; seen = 0; cr = 0; cn = 0; flat = 0; prevb = 0
    for (i = 1; i <= n; i++) {
        kd = kind[i]
        if (kd == "B") {
            flushcont(); cr = 0; flat = 0; btitle = ""; lastk = 0
            # a KV is a section only for the lines right below it
            while (nsec > 0 && skv[nsec]) nsec--
            if (seen) prevb = 1
            continue
        }
        if (kd == "C" || kd == "R") continue
        bstart = (prevb || !seen)
        if (prevb) { blk++; prevb = 0 }
        seen = 1
        if (kd == "T") {
            flushcont(); cr = 0; flat = 0; btitle = ""
            # a title with nothing under it (a banner over the next title) is a row
            if (banner != "" && !brows) emit("", "", banner)
            banner = tx[i]; brows = 0; nsec = 0
            continue
        }
        d = ind[i]
        # continuation of the last KV: a deeper TEXT line, or one at the KV
        # indent that carries on a comma list (a value wrapped to the margin)
        if (cr && kd == "O" && (d > cind || (d == cind && !bul[i] && index(tx[i], ": ") == 0 && (tx[i] ~ /, / || (cn ? cl[cn] : rval[cr]) ~ /,$/)))) { cl[++cn] = tx[i]; continue }
        flushcont(); cr = 0
        # flat (unindented) list under a header
        if (flat && kd == "O" && d == find && !bul[i]) { emit(fpath, fkey, tx[i]); continue }
        flat = 0
        while (nsec > 0 && sind[nsec] >= d) {
            if (sind[nsec] == d && bul[i] && slist[nsec] && !sbul[nsec]) break
            nsec--
        }
        # right-aligned keys (`   shell level : 1` under `active env location : x`)
        # share a colon column with the key line just before: siblings, not
        # children
        while (nsec > 0 && (kd == "K" || kd == "H") && scc[nsec] && scc[nsec] == cc[i] && sline[nsec] == lastk) nsec--
        if (kd == "K") {
            r = emit(path(nsec), kk[i], vv[i])
            if (!ralign) { nsec++; sind[nsec] = d; sname[nsec] = kk[i]; slist[nsec] = 0; sbul[nsec] = bul[i]; scc[nsec] = cc[i]; sline[nsec] = i; skv[nsec] = 1 }
            cr = r; cind = d; cn = 0; lastk = i
            continue
        }
        if (kd == "H") {
            p0 = path(nsec)
            nsec++; sind[nsec] = d; sname[nsec] = kk[i]; slist[nsec] = 1; sbul[nsec] = bul[i]; scc[nsec] = cc[i]; sline[nsec] = i; skv[nsec] = 0
            lastk = i
            j = (i < n ? i + 1 : 0)
            if (j && kind[j] == "O" && ind[j] == d && !bul[j]) { flat = 1; find = d; fkey = kk[i]; fpath = p0; continue }
            # a header with nothing under it is a key with an empty value
            j = nextdata(i, 1)
            if (!j || !(ind[j] > d || (ind[j] == d && bul[j] && !bul[i]))) { nsec--; emit(p0, kk[i], "") }
            continue
        }
        # TEXT
        if (nsec > 0 && slist[nsec]) { emit(path(nsec - 1), sname[nsec], tx[i]); continue }
        j = nextdata(i)
        # a short line opening a block, over lines at its own indent: the
        # block title (`support` over `issues : ...`), until the next blank
        if (bstart && nsec == 0 && !bul[i] && j && ind[j] == d && length(tx[i]) <= 40 && index(tx[i], ":") == 0 && titlelike(tx[i])) {
            t = tx[i]
            if (gsub(/[ \t]+/, " ", t) < 4) { btitle = tx[i]; continue }
        }
        if (j && ind[j] > d && titlelike(tx[i])) {
            nsec++; sind[nsec] = d; sname[nsec] = tx[i]; slist[nsec] = 0; sbul[nsec] = bul[i]; scc[nsec] = 0; skv[nsec] = 0
            continue
        }
        emit(path(nsec), "", tx[i])
    }
    flushcont()
    if (banner != "" && !brows) emit("", "", banner)
    # ONE RECORD (every row keyed, no key name repeated): one wide
    # row, a column per key named `section.key` — the shape the single-record
    # kv parsers give. Otherwise the long key/value table.
    wide = (nr > 0)
    for (r = 1; r <= nr && wide; r++) {
        if (rkey[r] == "" || (rkey[r] in wseen)) wide = 0
        wseen[rkey[r]] = 1
    }
    if (wide) {
        for (r = 1; r <= nr; r++) {
            nm = rsec[r]; gsub(/ > /, ".", nm)
            nm = nm (nm == "" ? "" : ".") rkey[r]; gsub(/[ \t]+/, "_", nm)
            print nm " " rval[r]
        }
        exit
    }
    for (r = 1; r <= nr; r++) {
        if (anysec) print "entry" r ".section " rsec[r]
        print "entry" r ".key " rkey[r]
        print "entry" r ".value " rval[r]
        if (rep) print "entry" r ".block " rblk[r]
    }
    if (nr) print "total_entries " nr
}
'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # RESCUE ONLY (see header): never competes in the ordinary ranking.
    [[ "${_FR_RESCUE:-0}" -eq 1 || "${_OPT_strategy:-}" == kv-report ]] || return 1
    [[ "$text" == *:* || "$text" == *" = "* ]] || return 1
    local _v
    _v="$(printf '%s\n' "$text" | _KVR_MODE=detect LC_ALL=C awk "$_KVR_AWK")"
    [[ "$_v" == yes ]] || return 1
    _STRATEGY_CONFIDENCE=70
    _STRATEGY_CONFIDENCE_REASON="key/value report with list sections (coverage rescue)"
    return 0
}

strategy_extract () {
    local text="$1"
    printf '%s\n' "$text" | _KVR_MODE=extract LC_ALL=C awk "$_KVR_AWK"
}
