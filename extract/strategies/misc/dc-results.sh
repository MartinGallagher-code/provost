#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: dc-results
## Description: The datacenter floor-plan viewer's results format: `test target value [key=value ...]` samples under `!test` metadata lines (mx export, iperf export-overlay, reckon --overlay, dcprobe, dcimport)
## Version: 1.0
## Priority: 12
## Sample: samples/dc-results/basic.txt

# datacenter_visualization paints a floor plan from a results file, and the
# toolchain's measuring tools write one: `mx export`, iperf_orchestrator's
# export-overlay, reckon --overlay, dcprobe, dcimport. A line is a sample,
#
#     test  target  value  [key=value ...]
#
# its fields separated by tabs, commas or runs of spaces — except inside
# quotes, '…' or "…" opening a field or a value, which are not kept. Display
# metadata for a test comes on its own line,
#
#     !test  NAME  unit=us higher=bad label="RTT p99"
#
# and `#` lines are comments. Read as a table that is a generic TSV with
# phantom columns `A B C D` — `!test` lines as rows, each sample's `k=v`
# fields as cells nobody can query. Here each sample is a row: test, target,
# value, then its own keys, then its test's metadata (a key the sample sets
# itself keeps the sample's value). A key named test, target or value is
# `meta_<key>`, as the viewer's own readers name it.
#
# Detected by its `!test` lines only. A results file written without them
# (`--no-meta`) is three words and a number per line, which ordinary output
# (`cpu0 user 123`) is too; those are left to the generic parsers.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local nl=$'\n'
    local re_meta='(^|'"$nl"')[[:space:]]*!test[[:space:],]+[^[:space:],]'
    [[ "$text" =~ $re_meta ]] || return 1
    # …and at least one sample: a line that is not a comment or a `!` line,
    # with three fields or more
    printf '%s\n' "$text" | awk '
        { s = $0; sub(/^[ \t]+/, "", s) }
        s == "" || substr(s, 1, 1) == "#" || substr(s, 1, 1) == "!" { next }
        { n = split(s, f, /[ \t,]+/); if (n >= 3) { found = 1; exit } }
        END { exit !found }' || return 1
    _STRATEGY_CONFIDENCE=92
    _STRATEGY_CONFIDENCE_REASON="!test metadata lines over test/target/value samples"
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        # The format field rule: tabs, commas, runs of spaces; a quote opening
        # a field or following `=` runs to its match and is not kept.
        function split_fields(s,   i, n, c, cur, q, have, nf) {
            nf = 0; cur = ""; q = ""; have = 0; n = length(s)
            for (i = 1; i <= n; i++) {
                c = substr(s, i, 1)
                if (q != "") { if (c == q) q = ""; else cur = cur c; continue }
                if ((c == "\"" || c == "\047") && \
                    (cur == "" || substr(cur, length(cur), 1) == "=")) {
                    q = c; have = 1; continue
                }
                if (c == "\t" || c == "," || c == " ") {
                    if (cur != "" || have) { F[++nf] = cur; cur = ""; have = 0 }
                    continue
                }
                cur = cur c
            }
            if (cur != "" || have) F[++nf] = cur
            return nf
        }
        function key(k) {
            gsub(/[ \t]+/, "_", k)
            if (k == "test" || k == "target" || k == "value") k = "meta_" k
            return k
        }
        {
            s = $0; sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s)
            if (s == "" || substr(s, 1, 1) == "#") next
            nf = split_fields(s)
            if (F[1] == "!test") {
                # NAME, then its metadata, in the order written
                if (nf < 2) next
                t = F[2]
                if (!(t in NMETA)) NMETA[t] = 0
                for (j = 3; j <= nf; j++) {
                    e = index(F[j], "=")
                    if (e < 2) continue
                    NMETA[t]++
                    MK[t, NMETA[t]] = key(substr(F[j], 1, e - 1))
                    MV[t, NMETA[t]] = substr(F[j], e + 1)
                }
                next
            }
            if (substr(F[1], 1, 1) == "!" || nf < 3) next
            n++
            TEST[n] = F[1]; TARGET[n] = F[2]; VALUE[n] = F[3]; NKV[n] = 0
            for (j = 4; j <= nf; j++) {
                e = index(F[j], "=")
                if (e < 2) continue
                NKV[n]++
                KK[n, NKV[n]] = key(substr(F[j], 1, e - 1))
                KV[n, NKV[n]] = substr(F[j], e + 1)
            }
        }
        END {
            for (i = 1; i <= n; i++) {
                p = "entry" i "."
                print p "test " TEST[i]
                print p "target " TARGET[i]
                print p "value " VALUE[i]
                split("", have)
                for (j = 1; j <= NKV[i]; j++) {
                    print p KK[i, j] " " KV[i, j]
                    have[KK[i, j]] = 1
                }
                t = TEST[i]
                if (t in NMETA)
                    for (j = 1; j <= NMETA[t]; j++)
                        if (!(MK[t, j] in have)) print p MK[t, j] " " MV[t, j]
            }
            if (n > 0) print "total_entries " n
        }'
}
