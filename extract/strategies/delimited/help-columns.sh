#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: help-columns
## Description: Help text and command listings — indented `term   description` entries under section titles (--help, cargo --list, npm run, rake -T); wrapped descriptions joined -> section/name/description
## Version: 1.0
## Priority: 46
## Confidence-Max: 82
## Sample: samples/help-columns/basic.txt

# `--help` pages and command listings print one entry per option or command:
# an indented TERM, a gap of two or more spaces, and a free-text DESCRIPTION
# aligned in a column, grouped under section titles:
#
#   Global Options:
#         --config string      Location of client config files
#     -c, --context string     Name of the context to use
#     -C DIRECTORY, --directory=DIRECTORY
#                              Change to DIRECTORY before doing anything.
#
# two-col-gap (the unindented `key   free text` shape) cannot take these: the
# entries are indented, a term may hold single spaces (`-c, --context
# string`), a description may wrap onto lines at its own column, a term may
# stand alone over its description, and the titles are not entries. They fell
# to aligned-columns (descriptions shredded one word per column),
# indented-colon-groups (term and description welded into one value) or
# text-lines. Tidied, each entry is a row:
#
#   section         name                   description
#   Global Options  --config string        Location of client config files
#   Global Options  -c, --context string   Name of the context to use
#
# ENTRIES. A gap entry is an indented line (or, in the `name   # comment`
# form of just / rake -T, any line) split at its first 2+-space run (wget's
# `-V,` then `--version` stay one term); the term is short
# (<= 48 chars, <= 6 words, not a sentence, not `x = "y"`). A term alone on
# its line is an entry when the next line is its description: at the list's
# description column, or — in a list made only of such pairs (npm run) —
# every term at one indent and every description one level deeper.
# CONTINUATION: a deeper line at the description column (or without a gap of
# its own) extends the description above. TITLES: a short line (ending in
# `:`, or <= 64 chars and not a sentence) less indented than the entry under
# it names the `section` of the entries below. Any other line (usage, prose,
# footers) is a row holding only its text in `description`.
#
# NOT HELP TEXT. Indented tables share the gap, so detection asks for the
# help shape: >= 3 entries; descriptions aligned (>= 70% share their column
# with another entry of their section); >= 60% multi-word descriptions that
# read as prose (open with a letter / quote / bracket, carry a lowercase
# word) and hold no further 2+-space column gap (<= 15%); terms that are
# words or option lists (not numbers, not `key:` / `key=` labels); no `|`
# cells; the second words of the descriptions not lined up in one column.
#
# CONFIDENCE 82 with >= 5 entries, >= 90% aligned and >= 50% of the lines
# explained (entries, continuations, titles) — help pages carry usage lines
# and prose, so the bar is the entries, not every line; otherwise 78 (>= 60%
# explained). 82 clears the 80 of the generic group parsers that claimed
# these pages before (indented-colon-groups, block-records), stays under the
# grammar tier (85).

_hc_awk () {
    awk -v MODE="$1" -v SLACK="${_FR_SLACK:-0}" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # leading tabs expand to 8-column stops (go help); an inner tab is a gap
    function detab(s,    lead, rest, p, c, out) {
        match(s, /^[ \t]*/); lead = substr(s, 1, RLENGTH); rest = substr(s, RLENGTH + 1)
        out = ""
        for (p = 1; p <= length(lead); p++) {
            c = substr(lead, p, 1)
            if (c == "\t") { do out = out " "; while (length(out) % 8) }
            else out = out " "
        }
        gsub(/\t/, "  ", rest)
        return out rest
    }
    # line j opens an entry: a gap entry, or a term over a deeper description
    function entryish(j,    k) {
        if (IND[j] < 1) return 0
        if (GE[j]) return 1
        k = j + 1; while (k <= N && BL[k]) k++
        return (k <= N && IND[k] >= IND[j] + 2 && length(trim(L[j])) <= 48)
    }
    {
        sub(/\r$/, "")
        s = $0
        if (index(s, "\t")) s = detab(s)
        N++; L[N] = s
        if (s !~ /[^ ]/) { BL[N] = 1; next }
        NB++
        match(s, /^ */); IND[N] = RLENGTH
        # gap entry: term (no 2+-space run) + 2+ spaces + description
        rest = substr(s, IND[N] + 1)
        gp = 0
        if (match(rest, /[^ ]  +[^ ]/)) {
            gp = RSTART
            # `-V,  --version   …` (wget): a short option and its comma run on
            # to the long form across the first gap
            if (substr(rest, 1, gp) ~ /^-[A-Za-z0-9?],$/ && match(substr(rest, gp + 1), /[^ ]  +[^ ]/)) gp += RSTART
        } else if (match(rest, /[^ ] #+ [^ ]/)) gp = RSTART
        if (gp) {
            term = substr(rest, 1, gp); gsub(/  +/, " ", term)
            desc = substr(rest, gp + 1); sub(/^ +/, "", desc)
            # `name   # what it does` (just --list, rake -T): a comment column
            cm = (desc ~ /^#+ /); sub(/^#+ +/, "", desc)
            sentence = (term ~ /[a-z][.!?]$/ && split(term, tw, / /) >= 3)
            if (length(term) <= 48 && !sentence && split(term, tw, / /) <= 6 && (IND[N] >= 1 || cm) && term !~ / = /) {
                GE[N] = 1; TERM[N] = term; DESC[N] = trim(desc)
                match(substr(rest, gp + 1), /^ *(#+ +)?/); DCOL[N] = IND[N] + gp + RLENGTH
                NDC[DCOL[N]]++; NGL++
            }
        }
    }
    END {
        slack = SLACK + 0
        # the role of every line: entry, continuation, section title, free line
        E = 0; Cn = 0; Hn = 0; F = 0; sect = ""; cur = 0
        for (i = 1; i <= N; i++) {
            if (BL[i]) continue
            nx = i + 1; while (nx <= N && BL[nx]) nx++
            if (nx > N) nx = 0
            hd = (nx && IND[i] < IND[nx] && entryish(nx) && (L[i] ~ /:[ ]*$/ || (length(trim(L[i])) <= 64 && L[i] !~ /[.][ ]*$/)))
            # continuation of the entry above: deeper than its term, and at (or
            # past) its description column, or holding no gap of its own
            if (cur > 0 && !(hd && (REC[cur] < 0 || IND[i] < DC[cur] - 1)) && IND[i] > IND[ABS[cur]] && (IND[i] >= DC[cur] - 1 || !GE[i]) && prevrole != "h" && (REC[cur] > 0 || !entryish(i))) {
                if (DS[cur] == "") DS[cur] = trim(L[i]); else DS[cur] = DS[cur] " " trim(L[i])
                if (DC[cur] == 0) DC[cur] = IND[i]
                if (REC[cur] > 0) Cn++; else F++
                prevrole = "c"; continue
            }
            if (GE[i]) {
                E++; NR_++; cur = NR_; REC[cur] = i; ABS[cur] = i; NM[cur] = TERM[i]; DS[cur] = DESC[i]; DC[cur] = DCOL[i]; SEC[cur] = sect
                KIND[cur] = "g"; prevrole = "e"; continue
            }
            # a term alone on its line over a deeper description: in an aligned
            # list the description sits at the description column (make
            # `-C DIR, --directory=DIR`); in a list of such pairs (npm run) see
            # the structure check below
            if (IND[i] >= 1 && !GE[i] && nx && IND[nx] >= IND[i] + 2 && !GE[nx] && length(trim(L[i])) <= 48 && split(trim(L[i]), tw, / /) <= 4 && (NGL < 2 ? 1 : (NDC[IND[nx]] >= 2))) {
                E++; NR_++; cur = NR_; REC[cur] = i; ABS[cur] = i; NM[cur] = trim(L[i]); DS[cur] = ""; DC[cur] = 0; SEC[cur] = sect; ISTERM[i] = 1
                KIND[cur] = "t"; prevrole = "e"; continue
            }
            # section header: a short, less-indented title right above an entry
            # (`Options:`, `CORE COMMANDS`, git `start a working area (...)`);
            # a sentence ending in `.` is prose, not a title
            if (hd) {
                sect = trim(L[i]); sub(/:$/, "", sect)
                Hn++; prevrole = "h"; cur = 0; continue
            }
            F++; NR_++; cur = NR_; REC[cur] = -i; ABS[cur] = i; DS[cur] = trim(L[i]); DC[cur] = 0; prevrole = "f"
        }
        # evidence
        ng = 0; al = 0; multi = 0
        for (r = 1; r <= NR_; r++) {
            if (REC[r] <= 0) continue
            if (KIND[r] == "g") { ng++; DCN[SEC[r], DC[r]]++ }
            if (DS[r] ~ / /) multi++
        }
        for (r = 1; r <= NR_; r++) if (REC[r] > 0 && KIND[r] == "g" && DCN[SEC[r], DC[r]] >= 2) al++
        # free text, not a grid: the second word of multi-word descriptions does
        # not sit at one column
        nw2 = 0; w2top = 0
        for (r = 1; r <= NR_; r++) {
            if (REC[r] <= 0 || KIND[r] != "g" || DS[r] !~ / /) continue
            match(DS[r], / +/); off = DC[r] + RSTART + RLENGTH
            W2[off]++; nw2++; if (W2[off] > w2top) w2top = W2[off]
        }
        # help-text shape, not a table: terms are words or option lists (not
        # numbers, not `key:` labels), descriptions are single-spaced prose
        tok_ = 0; tcolon = 0; dgap = 0; dprose = 0; pipes = 0
        for (r = 1; r <= NR_; r++) {
            if (REC[r] <= 0) continue
            i = REC[r]
            if (NM[r] ~ /^(--?)?[A-Za-z@.\/_<\[]/ && split(NM[r], tw, / /) <= 4) tok_++
            if (NM[r] ~ /[:=]$/) tcolon++
            if (KIND[r] == "g" && DESC[i] ~ /[^ ]  +[^ ]/) dgap++
            if (DS[r] ~ /^[A-Za-z`"(<\[]/ && DS[r] ~ /[a-z][a-z][a-z]/) dprose++
            if (L[i] ~ /[|]|│|┃/) pipes++
        }
        cov = int((E + Cn + Hn) * 100 / NB)
        if (MODE == "detect") {
            if (E < 3) { print "0 few"; exit }
            # a list of term-over-description pairs only: every term at one
            # indent, every description one level deeper, nothing deeper, and the
            # descriptions are not `label: value` lines (a tree / a kv hierarchy)
            if (ng == 0) {
                ti = -1; di = -1
                for (i = 1; i <= N; i++) {
                    if (BL[i] || IND[i] == 0) continue
                    if (i in ISTERM) { if (ti < 0) ti = IND[i]; else if (IND[i] != ti) { print "0 term-indent"; exit } }
                    else {
                        if (di < 0) di = IND[i]; else if (IND[i] != di) { print "0 desc-indent"; exit }
                        if (L[i] ~ /^ *[A-Za-z][A-Za-z ]*: /) { print "0 desc-label"; exit }
                    }
                }
                if (ti < 0 || di <= ti) { print "0 structure"; exit }
            }
            # (every share threshold widens by the sample slack in the accepting
            # direction, see extract/README.md "Very large inputs")
            if (ng > 0 && al * 100 < ng * (70 - slack)) { print "0 unaligned " al "/" ng; exit }
            if (multi * 100 < E * (60 - slack)) { print "0 single-word"; exit }
            if (tok_ * 100 < E * (80 - slack) || tcolon * 100 >= E * (30 + slack)) { print "0 terms"; exit }
            if (dgap * 100 > ng * (15 + slack) || dprose * 100 < E * (70 - slack) || pipes * 100 >= E * (30 + slack)) { print "0 not-prose"; exit }
            if (nw2 >= 3 && w2top * 100 >= nw2 * (80 + slack)) { print "0 grid"; exit }
            if (cov < 50 - slack) { print "0 cov " cov; exit }
            conf = (E >= 5 && al * 10 >= ng * 9 && cov >= 50) ? 82 : 78
            if (cov < 60 - slack && conf < 82) { print "0 cov " cov; exit }
            print conf, "E=" E, "C=" Cn, "H=" Hn, "F=" F, "cov=" cov, "al=" al "/" ng
            exit
        }
        hs = (Hn > 0)
        for (r = 1; r <= NR_; r++) {
            if (REC[r] > 0) { nm = NM[r]; ds = DS[r]; se = SEC[r] }
            else { nm = ""; ds = DS[r]; se = "" }
            sub(/:$/, "", nm)
            gsub(/\t/, " ", ds)
            if (hs) printf "entry%d.section %s\n", r, se
            printf "entry%d.name %s\n", r, nm
            printf "entry%d.description %s\n", r, ds
        }
        printf "total_entries %d\n", NR_
    }
'
}

strategy_detect () {
    local text="$1" out
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON=""
    out="$(_hc_awk detect <<< "$text")" || return 1
    [[ "$out" =~ ^([0-9]+)\ (.*)$ ]] || return 1
    [[ "${BASH_REMATCH[1]}" -gt 0 ]] || return 1
    _STRATEGY_CONFIDENCE="${BASH_REMATCH[1]}"
    _STRATEGY_CONFIDENCE_REASON="help entries ${BASH_REMATCH[2]}"
    return 0
}

strategy_extract () {
    _hc_awk extract <<< "$1"
}
