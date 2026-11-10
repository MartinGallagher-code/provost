#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# provost/transform/units.sh — units as data (PV-032). First-party provost
# code; sourced by `provost` beside melt.sh.
#
# Functions: _core_units_base IN OUT MAP [TOOL...]  (a tidy dataset file)
#            _core_units_cell                         (one cell a line, for tests)
#
# WHERE A UNIT LIVES IN TIDY OUTPUT. provost never moves or converts a unit
# unasked: by default it stays where the tool printed it, in the column's name
# (`Bandwidth_(MB/s)`, `Best_Rate_MB/s`), in each cell (`482MiB/s`,
# `1.19 MBytes`), or in a column of its own beside the number (`transfer` +
# `transfer_unit`, as some tool strategies emit). With `--units base`
# (PROVOST_UNITS=base) every column whose unit can be read exactly gains a
# sibling column, right after it, named `NAME[UNIT]`: the same values as plain
# decimal numbers in a base unit, so that `9.4 GB/s` and `9400 MB/s` become the
# same number. The original column is kept as it was. The base units:
#
#   B       bytes             bit      bits
#   B/s     bytes a second    bit/s    bits a second
#   s       seconds
#
# Bits are never turned into bytes, nor bytes into bits: they stay different
# units, so a consumer comparing `B/s` with `bit/s` sees that they differ.
#
# HOW A UNIT IS READ: by the letter.
#   * `B`, `Byte(s)` are bytes; `b`, `bit(s)` are bits (a bare `b` with no
#     prefix is not read: too many other meanings).
#   * Decimal prefixes k, K, M, G, T, P, E are powers of 1000; binary prefixes
#     Ki, Mi, Gi, Ti, Pi, Ei are powers of 1024. A tool that prints `kB` for
#     1024 bytes (/proc/meminfo) is converted as printed; the original column
#     still says what the tool said.
#   * A rate is a size unit followed by `/s` or `/sec`, or `ps` after a short
#     form (`MBps`, `Mbps`).
#   * Times: ns/nsec, us/usec/µs/μs, ms/msec, s/sec/secs/second(s).
#   * A bare multiplier with no quantity (`7.8Gi`, `1.2G`, `128K`, as
#     `free -h` and `df -h` print) is NOT read: coreutils' `G` means 1024^3,
#     the letter says 1000^3, and neither says bytes. Nothing is guessed.
#   * One exception to "by the letter", from the tools' own source: iperf2 and
#     iperf3 print byte counts and byte rates in powers of 1024 under the labels
#     KBytes, MBytes, GBytes, TBytes (iperf3 src/units.c, iperf2 src/stdio.c),
#     so a dataset parsed by `iperf3-intervals`, or named `iperf` or `iperf3`
#     (as `provost run iperf3 ...` names it), reads them as KiB, MiB, GiB, TiB.
#     Their bit rates (Mbits/sec) are powers of 1000, as labelled.
#
# WHICH COLUMNS. A column is converted only when every cell holding a digit can
# be read; a cell with no digit (empty, `-`, `N/A`) gives an empty converted
# cell. Where the unit comes from, in this order:
#   1. its name: a trailing `(UNIT)` or `[UNIT]` (`Latency (us)`,
#      `bw(MiB/s)`; a one-letter unit only after a space or `_`: `Time_(s)`,
#      never the plural in `Error(s)`); the whole name (`MB/s`); or the last
#      `_`- or space-separated word when it carries a prefix or a rate
#      (`Best_Rate_MB/s`, `rtt_ms`; not `kb_read_s`, `requests_per_ms`, or a
#      bare `s` or `bytes`). Every digit-bearing cell must then be a plain
#      number.
#   2. a column named NAME_unit beside it: each row's number is read in that
#      row's unit.
#   3. each cell: a number, then optionally spaces or one `_`, then a unit
#      (`482MiB/s`, `1.19 MBytes`, `42.18_GiB`), optionally followed by the
#      same quantity in another unit in parentheses (fio's
#      `482MiB/s (505MB/s)`: the first is used).
# All of a column's units must be the same quantity (sizes, or byte rates, or
# bit rates, or times), else the column is left alone.
#
# EXACT. Every factor is a power of 10 or of 1024, so the converted value is
# computed digit by digit on the decimal string — never in floating point,
# which loses precision past 2^53 — and printed in full (no exponent, no
# trailing zeros): `28.2GiB` -> 30279519436.8, `9.98 Mbits/sec` -> 9980000,
# `0.041 ms` -> 0.000041.
#
# THE RECORD. MAP gets one line per converted column:
#   column <TAB> unit_column <TAB> base unit <TAB> from <TAB> read
# where `from` is `name`, `cells` or `column NAME_unit`, and `read` lists each
# unit read with its exact factor: `MB/s=10^6`, `MiB/s=2^20`,
# `MBytes=2^20 (iperf)`, `ms=10^-3`. provost files it with the capture as
# units.tsv.
#
# Arguments reach awk through ENVIRON, never `awk -v` (which rewrites
# backslash escapes in a value). mawk-safe: no gawk-only functions, no regex
# intervals.

_CORE_UNITS_LIB='
function _u_init(   si, se, iec, n, i, j, p, s, bsfx, nb, bisfx, nbi, rr, t, tools, k) {
    NUMRE = "^[-+]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][-+]?[0-9]+)?"
    n = split("k K M G T P E", si, " "); split("1 1 2 3 4 5 6", se, " ")
    split("Ki Mi Gi Ti Pi Ei", iec, " ")
    nb = split("B Byte Bytes", bsfx, " ")
    nbi = split("bit bits Bit Bits b", bisfx, " ")
    # bytes
    split("B Byte Bytes byte bytes", t, " ")
    for (j = 1; j <= 5; j++) _u_def(t[j], "B", 0, 0)
    for (i = 1; i <= n; i++) for (j = 1; j <= nb; j++) _u_def(si[i] bsfx[j], "B", 3 * se[i], 0)
    for (i = 1; i <= 6; i++) _u_def(iec[i] "B", "B", 0, i)
    # bits (a bare `b` is not a unit here; a prefixed one is)
    split("bit bits Bit Bits", t, " ")
    for (j = 1; j <= 4; j++) _u_def(t[j], "bit", 0, 0)
    for (i = 1; i <= n; i++) for (j = 1; j <= nbi; j++) _u_def(si[i] bisfx[j], "bit", 3 * se[i], 0)
    for (i = 1; i <= 6; i++) for (j = 1; j <= nbi; j++) _u_def(iec[i] bisfx[j], "bit", 0, i)
    # rates: every size unit over /s and /sec; `ps` after a short form
    for (k in DIM) {
        if (DIM[k] != "B" && DIM[k] != "bit") continue
        rr[k "/s"] = k; rr[k "/sec"] = k
        if (k ~ /^([kKMGTPE]|[KMGTPE]i)?[Bb]$/) rr[k "ps"] = k
    }
    for (k in rr) _u_def(k, DIM[rr[k]] "/s", E10[rr[k]], N2[rr[k]])
    _u_def("bps", "bit/s", 0, 0); _u_def("b/s", "bit/s", 0, 0)
    # times
    split("ns nsec nsecs", t, " ");                 for (j = 1; j <= 3; j++) _u_def(t[j], "s", -9, 0)
    split("us usec usecs \302\265s \316\274s", t, " "); for (j = 1; j <= 5; j++) _u_def(t[j], "s", -6, 0)
    split("ms msec msecs", t, " ");                 for (j = 1; j <= 3; j++) _u_def(t[j], "s", -3, 0)
    split("s sec secs second seconds", t, " ");     for (j = 1; j <= 5; j++) _u_def(t[j], "s", 0, 0)
    # base words: read inside (...) and in cells, never as a bare column-name word
    split("s sec secs second seconds B b bit bits Bit Bits Byte Bytes byte bytes", t, " ")
    for (j in t) BARE[t[j]] = 1
    # tool conventions (see the header comment): iperf byte labels are binary
    n = split(ENVIRON["UNITS_TOOLS"], tools, " ")
    for (i = 1; i <= n; i++) {
        if (tools[i] != "iperf" && tools[i] != "iperf3" && tools[i] != "iperf3-intervals") continue
        split("K M G T", t, " ")
        for (j = 1; j <= 4; j++) {
            for (k = 0; k < 3; k++) {
                s = (k == 0) ? "" : (k == 1) ? "/s" : "/sec"
                RE[t[j] "Byte" s] = t[j] "iB" s; RE[t[j] "Bytes" s] = t[j] "iB" s
                REW[t[j] "Byte" s] = REW[t[j] "Bytes" s] = "iperf"
            }
        }
    }
}
function _u_def(u, d, e, b) { DIM[u] = d; E10[u] = e; N2[u] = b }
# the unit a written unit is converted as: itself, or a tool convention
function _u_map(u) { return (u in RE) ? RE[u] : u }
function _u_trim(s) { sub(/^[ ]+/, "", s); sub(/[ ]+$/, "", s); return s }
# a number _u_base can take: the regex, and an exponent of at most 60
function _u_numok(x,   p) {
    if (!match(x, NUMRE) || RLENGTH != length(x)) return 0
    p = match(x, /[eE]/)
    if (p && (substr(x, p + 1) + 0 > 60 || substr(x, p + 1) + 0 < -60)) return 0
    return 1
}
# _u_cell(s): 1 when s is NUMBER [spaces | _] UNIT [ " (" NUMBER [sep] UNIT ")" ]
# with a readable unit, setting _UV (the number) and _UU (the unit as written)
function _u_cell(s,   num, rest, alt, i, u, au) {
    s = _u_trim(s)
    if (!match(s, NUMRE)) return 0
    num = substr(s, 1, RLENGTH); rest = substr(s, RLENGTH + 1)
    if (!_u_numok(num)) return 0
    if (substr(rest, 1, 1) == "_") rest = substr(rest, 2); else sub(/^ +/, "", rest)
    i = index(rest, " (")
    if (i > 0) {
        u = substr(rest, 1, i - 1); alt = substr(rest, i + 2)
        if (substr(alt, length(alt), 1) != ")") return 0
        alt = substr(alt, 1, length(alt) - 1)
        if (!match(alt, NUMRE)) return 0
        au = substr(alt, RLENGTH + 1)
        if (!_u_numok(substr(alt, 1, RLENGTH))) return 0
        if (substr(au, 1, 1) == "_") au = substr(au, 2); else sub(/^ +/, "", au)
        if (!(_u_map(au) in DIM) || au == "b") return 0
        if (!(_u_map(u) in DIM) || DIM[_u_map(u)] != DIM[_u_map(au)]) return 0
    } else u = rest
    if (u == "b" || !(_u_map(u) in DIM)) return 0
    _UV = num; _UU = u
    return 1
}
# the last index of character c in s (0 if none)
function _u_last(s, c,   i) { for (i = length(s); i > 0; i--) if (substr(s, i, 1) == c) return i; return 0 }
# _u_hdr(h): the unit a column name carries (as written), or ""
function _u_hdr(h,   n, c, o, p, u, q, pre) {
    n = length(h); c = substr(h, n, 1)
    if (c == ")" || c == "]") {
        o = (c == ")") ? "(" : "["
        p = _u_last(h, o)
        if (p < 1) return ""
        u = substr(h, p + 1, n - p - 1)
        if (u == "b" || !(_u_map(u) in DIM)) return ""
        if (length(u) > 1 || p == 1) return u
        q = substr(h, p - 1, 1)
        return (q == " " || q == "_") ? u : ""
    }
    if (!(h in BARE) && h != "b" && (_u_map(h) in DIM)) return h
    p = _u_last(h, "_"); q = _u_last(h, " "); if (q > p) p = q
    if (p < 2) return ""
    u = substr(h, p + 1); pre = substr(h, 1, p - 1)
    if (u in BARE || u == "" || !(_u_map(u) in DIM)) return ""
    if (pre ~ /(^|[_ ])[Pp]er$/) return ""
    return u
}
# d (a digit string) times m (a small whole number), as a digit string
function _u_mul(d, m,   i, c, r, x) {
    c = 0; r = ""
    for (i = length(d); i > 0; i--) { x = substr(d, i, 1) * m + c; r = (x % 10) r; c = int(x / 10) }
    while (c > 0) { r = (c % 10) r; c = int(c / 10) }
    return r
}
# _u_base(num, u): the number num, written in unit u (as converted: _u_map), in
# the base unit of u, exactly, as a plain decimal
function _u_base(num, u,   neg, e, p, ip, fp, d, sc, k, n, z, f) {
    neg = 0; f = substr(num, 1, 1)
    if (f == "-") { neg = 1; num = substr(num, 2) } else if (f == "+") num = substr(num, 2)
    e = 0; p = match(num, /[eE]/)
    if (p) { e = substr(num, p + 1) + 0; num = substr(num, 1, p - 1) }
    p = index(num, ".")
    if (p) { ip = substr(num, 1, p - 1); fp = substr(num, p + 1) } else { ip = num; fp = "" }
    d = ip fp; sc = length(fp) - e - E10[u]
    for (k = 0; k < N2[u]; k++) d = _u_mul(d, 1024)
    sub(/^0+/, "", d)
    if (d == "") return "0"
    if (sc <= 0) { for (k = 0; k < -sc; k++) d = d "0"; return (neg ? "-" : "") d }
    n = length(d)
    if (n <= sc) { z = ""; for (k = n; k <= sc; k++) z = z "0"; d = z d; n = length(d) }
    ip = substr(d, 1, n - sc); fp = substr(d, n - sc + 1)
    sub(/0+$/, "", fp)
    return (neg ? "-" : "") ip (fp == "" ? "" : "." fp)
}
# the exact factor of unit u (as written) to its base unit, for the record
function _u_factor(u,   m, f) {
    m = _u_map(u)
    if (N2[m] > 0) f = "2^" (10 * N2[m])
    else if (E10[m] != 0) f = "10^" E10[m]
    else f = "1"
    return u "=" f ((u in REW) ? " (" REW[u] ")" : "")
}
'

# _core_units_base IN OUT MAP [TOOL...] — IN, a tidy dataset (a header line and
# tab-separated rows), to OUT with a NAME[UNIT] column after every column whose
# unit can be read (see above); MAP gets one line per such column (truncated
# first). TOOLs name the strategy and the dataset, for the tool conventions.
# A file with no such column is copied unchanged.
_core_units_base () {
    local in="$1" out="$2" map="$3"; shift 3
    : > "$map"
    UNITS_TOOLS="$*" UNITS_MAP="$map" awk -F'\t' "$_CORE_UNITS_LIB"'
BEGIN { _u_init(); MAPF = ENVIRON["UNITS_MAP"] }
# pass 1: read the header, then judge every column on every row
NR == FNR {
    if (!hseen) {
        if (length($0) == 0) next
        hseen = 1; NC = NF
        for (i = 1; i <= NF; i++) { H[i] = $i; IDX[$i] = i; USED[$i] = 1 }
        for (i = 1; i <= NC; i++) {
            HU[i] = _u_hdr(H[i])
            if (HU[i] == "" && ((H[i] "_unit") in IDX)) PAIR[i] = IDX[H[i] "_unit"]
        }
        next
    }
    if (length($0) == 0) next
    for (i = 1; i <= NC; i++) {
        if (BAD[i]) continue
        c = $i
        if (c !~ /[0-9]/) continue
        c = _u_trim(c)
        if (HU[i] != "") {
            if (_u_numok(c)) OKC[i]++; else BAD[i] = 1
            continue
        }
        if (i in PAIR) {
            u = _u_trim($(PAIR[i]))
            if (!_u_numok(c) || u == "b" || !(_u_map(u) in DIM)) { BAD[i] = 1; continue }
        } else {
            if (!_u_cell(c)) { BAD[i] = 1; continue }
            u = _UU
        }
        d = DIM[_u_map(u)]
        if (D[i] == "") D[i] = d; else if (D[i] != d) { BAD[i] = 1; continue }
        if (!((i SUBSEP u) in SEEN)) { SEEN[i, u] = 1; RD[i] = RD[i] (RD[i] == "" ? "" : ",") _u_factor(u) }
        OKC[i]++
    }
    next
}
# pass 2: the plan (which columns, named what, where), then every line
!planned {
    if (length($0) == 0) { print; next }
    planned = 1; nout = 0
    for (j = 1; j <= NC; j++) {
        OUT[++nout] = j
        for (i = 1; i <= NC; i++) {
            if (!OKC[i] || BAD[i]) continue
            last = i; if ((i in PAIR) && PAIR[i] > last) last = PAIR[i]
            if (last != j) continue
            if (HU[i] != "") { D[i] = DIM[_u_map(HU[i])]; RD[i] = _u_factor(HU[i]); FROM[i] = "name" }
            else if (i in PAIR) FROM[i] = "column " H[PAIR[i]]
            else FROM[i] = "cells"
            nm = H[i] "[" D[i] "]"
            while (nm in USED) nm = "_" nm
            USED[nm] = 1; NEWN[i] = nm
            OUT[++nout] = -i; any = 1
            printf "%s\t%s\t%s\t%s\t%s\n", H[i], nm, D[i], FROM[i], RD[i] > MAPF
        }
    }
    if (!any) { print; next }
    line = ""
    for (k = 1; k <= nout; k++) line = line (k > 1 ? "\t" : "") (OUT[k] > 0 ? H[OUT[k]] : NEWN[-OUT[k]])
    for (k = NC + 1; k <= NF; k++) line = line "\t" $k
    print line
    next
}
{
    if (!any || length($0) == 0) { print; next }
    line = ""
    for (k = 1; k <= nout; k++) {
        j = OUT[k]
        if (j > 0) v = $j
        else {
            i = -j; c = $i; v = ""
            if (c ~ /[0-9]/) {
                c = _u_trim(c)
                if (HU[i] != "") v = _u_base(c, _u_map(HU[i]))
                else if (i in PAIR) v = _u_base(c, _u_map(_u_trim($(PAIR[i]))))
                else if (_u_cell(c)) v = _u_base(_UV, _u_map(_UU))
            }
        }
        line = line (k > 1 ? "\t" : "") v
    }
    for (k = NC + 1; k <= NF; k++) line = line "\t" $k
    print line
}' "$in" "$in" > "$out"
}

# _core_units_cell [TOOL...] — for tests: each stdin line is one cell; prints
# `VALUE<TAB>BASE<TAB>READ` for a cell that reads (as a cell of a column of
# its own would), else `-`.
_core_units_cell () {
    UNITS_TOOLS="$*" awk "$_CORE_UNITS_LIB"'
BEGIN { _u_init() }
{ if (_u_cell($0)) printf "%s\t%s\t%s\n", _u_base(_UV, _u_map(_UU)), DIM[_u_map(_UU)], _u_factor(_UU)
  else print "-" }'
}

# _core_units_header [TOOL...] — for tests: each stdin line is a column name;
# prints the unit it carries (as written), or `-`.
_core_units_header () {
    UNITS_TOOLS="$*" awk "$_CORE_UNITS_LIB"'
BEGIN { _u_init() }
{ u = _u_hdr($0); print (u == "" ? "-" : u) }'
}
