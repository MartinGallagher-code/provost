#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# provost/transform/types.sh — column types (PV-040). First-party provost
# code; sourced by `provost` beside melt.sh and units.sh.
#
# Functions: _core_types_update TYPES DATASET [SRC CAPID]  (record a capture)
#            _core_types_leaf                             (one cell a line, for tests)
#            _core_types_valid FILE                       (the file's own form)
#
# WHAT A COLUMN'S TYPE IS. Every cell a capture files is judged by the
# extract engine's own cell classifier (extract/lib/_ctype.awk, the `ctype`
# its consistency measure uses), and that class is folded into one word of a
# small public vocabulary, the cell's KIND:
#
#   integer    42, -7, 1,234            decimal   3.14, .5, 2.5e3
#   percent    37%, 12.5 %              time      10:23, 00:05:01 (a clock
#   duration   30ms, 5m, 1h30m, 5 days,           reading: a time of day or
#              2-03:04:05, 26:00:00               an elapsed time)
#   quantity   20G, 1.5 KiB, 100MB/s, $5          datetime  2026-11-13, Nov 13
#   address    10.0.0.1, ::1, aa:bb:..,              10:00, 2026-11-13T10:00Z,
#              10.0.0.1:443                          Mon, 5 days ago
#   version    2.4.1, v1.0, 1.2.3-rc1   hex       0x1f, 3f2a9c1, a uuid
#   path       /usr/bin, ~/x, http://.. boolean   yes, no, true, off, enabled
#   text       anything else: words, several words, punctuation
#
# A blank cell, and a placeholder (`-`, `n/a`, `none`, `null`, `?`, ...), is
# not judged. A bare `m` after a number is minutes; `M` is mega. A dotted
# quad whose parts are all at most 255 is an address. A dotted date
# (`2024.01.15`, `13.11.2026`) is a datetime when it can be one, else a
# version.
#
# The kinds are ordered by what holds what. A wider type holds every value a
# narrower one does, so a column is given the narrowest that fits:
#
#   integer < decimal < percent < quantity;  decimal < duration < quantity;
#   time < duration;  time < datetime;
#   address, version, hex, path, boolean < text;
#   quantity, datetime, text < mixed.
#
# A column's type, from the counts of its cells' kinds (all the cells every
# capture so far filed into it): the narrowest type that holds at least
# _CORE_TYPES_MIN (90) per cent of them; else `text` when more than half are
# words (text, path, version, ...: a column of names that holds some numbers
# is text); else `mixed`. A column with no judged cell yet is `empty`.
#
# ACROSS CAPTURES a column is never silently retyped. Each capture adds its
# counts, the type is decided again on the sums, and the result is JOINED
# with the type already recorded: the narrowest type that holds both. So a
# later capture can widen a column (integer to decimal, path to text), but
# a column whose cells change kind (numbers that became words, times that
# became sizes) has no type but `mixed` that holds both, and becomes
# `mixed`, and stays so; git's history keeps what it was before.
#
# THE FILE, datasets/types/NAME.tsv beside datasets/NAME.tsv (one per
# dataset; none for `unsorted`): a header and one line per column of the
# dataset, in the dataset's own order, provost's own two (`#` and the
# capture column) left out.
#
#   column  the column's name, as in the dataset's header
#   type    one of the vocabulary above, `mixed` or `empty`
#   share   per cent (an integer, rounded down) of the judged cells the type
#           holds; blank for `mixed` and `empty`
#   cells   how many cells have been judged (blank and placeholder cells
#           are not)
#   counts  KIND=N,... : how many of those cells were of each kind, in the
#           vocabulary's order, kinds with none left out; blank when none
#   set_by  the capture whose filing set the type as it is now (the first
#           to fill the column, or the one that widened or mixed it)

_CORE_TYPES_HDR=$'column\ttype\tshare\tcells\tcounts\tset_by'
_CORE_TYPES_KINDS="integer decimal percent time duration quantity datetime address version hex path boolean text"
_CORE_TYPES_MIN="${_CORE_TYPES_MIN:-90}"
if [[ "${BASH_SOURCE[0]}" == */* ]]; then _CORE_TYPES_DIR="${BASH_SOURCE[0]%/*}"; else _CORE_TYPES_DIR=.; fi
_CORE_CTYPE_FILE="${_CORE_CTYPE_FILE:-$_CORE_TYPES_DIR/../extract/lib/_ctype.awk}"
_CORE_CTYPE_AWK=""

# The awk that follows extract/lib/_ctype.awk's functions. Files, in order:
# HDRF (one line: the dataset's header), OLD (the types recorded so far, or
# /dev/null), SRC (the rows to judge: one capture's, header first, or the
# whole dataset); the first two are named again in _TY_HDRF and _TY_OLDF (an
# empty file has no first line to count it by). MODE "leaf" reads one cell a
# line and prints its kind.
_CORE_TYPES_AWK='
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # the kind of a number with a unit (ctype N)
    function nleaf(v,   u) {
        if (v ~ /%$/) return "percent"
        if (v ~ /^[-+]?[0-9]+(,[0-9][0-9][0-9])+$/) return "integer"
        if (v ~ /^[-+]?[0-9]+(,[0-9][0-9][0-9])*\.[0-9]+$/) return "decimal"
        u = v; sub(/^[-+]?[$]?([0-9]+(,[0-9][0-9][0-9])*(\.[0-9]+)?|\.[0-9]+) ?/, "", u)
        if (u != "M" && (tolower(u) ~ DURU || tolower(u) ~ DURC)) return "duration"
        return "quantity"
    }
    # the kind of a date or time (ctype T)
    function tleaf(v,   lv, h) {
        lv = tolower(v)
        if (lv ~ /^[0-9]+-[0-9]+:[0-5][0-9](:[0-5][0-9])?([.,][0-9]+)?$/) return "duration"
        sub(/ ?(am|pm|z|utc|gmt)$/, "", lv)
        if (lv ~ /^[0-9]+:[0-5][0-9](:[0-5][0-9])?([.,][0-9]+)?$/) {
            h = lv; sub(/:.*$/, "", h)
            return (h + 0 >= 24 ? "duration" : "time")
        }
        return "datetime"
    }
    # a dotted date or a calendar version (ctype U)
    function uleaf(v,   p, y, m, d) {
        split(v, p, ".")
        if (length(p[1]) == 4) { m = p[2] + 0; d = p[3] + 0 } else { d = p[1] + 0; m = p[2] + 0 }
        return (m >= 1 && m <= 12 && d >= 1 && d <= 31) ? "datetime" : "version"
    }
    # leaf(v): the cell'"'"'s kind, or "" for a blank or a placeholder
    function leaf(v,   c) {
        c = ctype(v)
        if (c == "E") return ""
        v = trim(v)
        if (c == "I") return "integer"
        if (c == "D") return "decimal"
        if (c == "N") return nleaf(v)
        if (c == "T") return tleaf(v)
        if (c == "A" || c == "Q") return "address"
        if (c == "U") return uleaf(v)
        if (c == "H") return "hex"
        if (c == "V") return "version"
        if (c == "P") return "path"
        if (c == "F") return "boolean"
        return "text"
    }
    # does type t hold kind k (k <= t)?
    function holds(t, k) { return index(UP[k], " " t " ") > 0 }
    # the narrowest type that holds both a and b
    function join(a, b,   i) {
        if (a == "" || a == "empty") return (b == "" ? "empty" : b)
        if (b == "" || b == "empty") return a
        if (!(a in UP) || !(b in UP)) return "mixed"
        for (i = 1; i <= NT; i++) if (holds(TY[i], a) && holds(TY[i], b)) return TY[i]
        return "mixed"
    }
    # how many of column c'"'"'s cells type t holds
    function cover(c, t,   i, s) {
        s = 0
        for (i = 1; i <= NK; i++) if (holds(t, KD[i])) s += CNT[c, KD[i]]
        return s
    }
    # the type the counts of column c decide
    function decide(c,   n, i, w) {
        n = CELLS[c]
        if (n == 0) return "empty"
        for (i = 1; i < NT; i++) if (cover(c, TY[i]) * 100 >= MIN * n) return TY[i]
        w = cover(c, "text")
        return (w * 2 > n) ? "text" : "mixed"
    }
    # fold one group'"'"'s counts (one capture'"'"'s cells) into the record
    # (the type recorded so far is read through an `in` test, never passed
    # to a function as T[c] while it may not exist: gawk 5.2.1 corrupts its
    # heap on an array element made that way)
    function flush(   j, c, i, k, ot, nt) {
        for (j = 1; j <= NG; j++) {
            c = GC[j]
            for (i = 1; i <= NK; i++) { k = KD[i]; if ((c, k) in G) { CNT[c, k] += G[c, k]; CELLS[c] += G[c, k]; delete G[c, k] } }
            ot = (c in T) ? T[c] : ""
            nt = join(ot, decide(c))
            if (nt != ot) { T[c] = nt; SB[c] = GID }
            delete GT[c]
        }
        NG = 0
    }
    BEGIN {
        cons_init()
        MIN = (MIN == "" ? 90 : MIN + 0)
        NK = split(KINDS, KD, " ")
        NT = split(KINDS " mixed", TY, " ")
        # the types that hold each kind, narrowest first (see the order above)
        UP["integer"]  = " integer decimal percent duration quantity mixed "
        UP["decimal"]  = " decimal percent duration quantity mixed "
        UP["percent"]  = " percent quantity mixed "
        UP["time"]     = " time duration quantity datetime mixed "
        UP["duration"] = " duration quantity mixed "
        UP["quantity"] = " quantity mixed "
        UP["datetime"] = " datetime mixed "
        UP["address"]  = " address text mixed "
        UP["version"]  = " version text mixed "
        UP["hex"]      = " hex text mixed "
        UP["path"]     = " path text mixed "
        UP["boolean"]  = " boolean text mixed "
        UP["text"]     = " text mixed "
        UP["mixed"]    = " mixed "
        # duration units: a bare m is minutes (M is mega); 1h30m, 2d3h4m5s
        DURU = "^(ns|us|µs|μs|ms|s|sec|secs|seconds?|m|min|mins|minutes?|h|hr|hrs|hours?|d|days?|w|wk|wks|weeks?|mo|mos|months?|y|yr|yrs|years?)$"
        DURC = "^[wdhms]([0-9]+(\\.[0-9]+)?(ms|us|ns|[wdhms]))+$"
        if (MODE == "leaf") { while ((getline _line) > 0) { _k = leaf(_line); print (_k == "" ? "-" : _k) } ; exit }
    }
    # (the rules below use only names that start with _, which no function
    # above has as a local: gawk can abort on a local shadowing a global of
    # another kind)
    # the dataset'"'"'s header: the order of the columns, provost'"'"'s two left out
    FILENAME == ENVIRON["_TY_HDRF"] {
        _n = split($0, _H, "\t"); _st = (_H[1] == "#") ? ((_n >= 2 && _H[2] ~ /^_*capture$/) ? 3 : 2) : 1
        for (_i = _st; _i <= _n; _i++) if (!(_H[_i] in ORDQ)) { ORDQ[_H[_i]] = 1; ORD[++NO] = _H[_i] }
        next
    }
    # the types recorded so far
    FILENAME == ENVIRON["_TY_OLDF"] {
        if (FNR == 1) next
        _c = $1; if (_c in T) next
        T[_c] = $2; SB[_c] = $6; CELLS[_c] = 0
        _m = split($5, _P, ",")
        for (_i = 1; _i <= _m; _i++) {
            _k = _P[_i]; _q = index(_k, "="); if (!_q) continue
            _v = substr(_k, _q + 1) + 0; _k = substr(_k, 1, _q - 1)
            if ((_k in UP) && _k != "mixed") { CNT[_c, _k] += _v; CELLS[_c] += _v }
        }
        next
    }
    # the rows to judge
    FNR == 1 {
        _nc = split($0, _SH, "\t"); _cc = (_SH[1] == "#" && _nc >= 2 && _SH[2] ~ /^_*capture$/)
        _s0 = (_SH[1] == "#") ? (_cc ? 3 : 2) : 1
        GID = CAPID; NG = 0
        next
    }
    {
        if (CAPID == "" && _cc && $2 != GID) { if (NG) flush(); GID = $2 }
        for (_i = _s0; _i <= _nc; _i++) {
            _k = leaf($_i); if (_k == "") continue
            _c = _SH[_i]
            if (!(_c in GT)) { GT[_c] = 1; GC[++NG] = _c }
            G[_c, _k]++
        }
    }
    END {
        if (MODE == "leaf") exit
        if (NG) flush()
        print HDR
        for (_j = 1; _j <= NO; _j++) {
            _c = ORD[_j]; _t = (_c in T) ? T[_c] : "empty"; _n = CELLS[_c] + 0
            if (_n == 0 && _t != "mixed") _t = "empty"
            _sh = (_t == "mixed" || _t == "empty") ? "" : int(cover(_c, _t) * 100 / _n)
            _o = ""
            for (_i = 1; _i <= NK; _i++) if (CNT[_c, KD[_i]] > 0) _o = _o (_o == "" ? "" : ",") KD[_i] "=" CNT[_c, KD[_i]]
            print _c "\t" _t "\t" _sh "\t" _n "\t" _o "\t" (_t == "empty" ? "" : SB[_c])
        }
    }'

# _core_types_awk MODE CAPID [FILE...] — the program, on FILEs (or stdin)
_core_types_awk () {
    local mode="$1" capid="$2"; shift 2
    if [[ -z "$_CORE_CTYPE_AWK" ]]; then
        _CORE_CTYPE_AWK="$(cat "$_CORE_CTYPE_FILE" 2>/dev/null)" || _CORE_CTYPE_AWK=""
        [[ -n "$_CORE_CTYPE_AWK" ]] || { printf 'types: the cell classifier is missing (%s)\n' "$_CORE_CTYPE_FILE" >&2; return 1; }
    fi
    LC_ALL=C awk -F'\t' -v MIN="$_CORE_TYPES_MIN" -v KINDS="$_CORE_TYPES_KINDS" -v HDR="$_CORE_TYPES_HDR" \
        -v MODE="$mode" -v CAPID="$capid" "$_CORE_CTYPE_AWK$_CORE_TYPES_AWK" "$@"
}

# _core_types_leaf — one cell a line on stdin, its kind a line on stdout
# ("-" for a blank or a placeholder). For tests.
_core_types_leaf () { _core_types_awk leaf ""; }

# _core_types_update TYPES DATASET [SRC CAPID [WORK]] — record a capture's cells.
#   TYPES    the dataset's types file; written whole (through TYPES.tmp)
#   DATASET  the dataset file as it now is (its header gives the columns)
#   SRC      the rows capture CAPID filed (a header line, then the rows),
#            folded into what TYPES recorded. Without SRC (or when TYPES does
#            not exist yet), every row DATASET holds is judged instead, one
#            capture at a time in the order they were filed (its capture
#            column), from nothing: a dataset filed before column types
#            existed gets the types it would have had, and a dataset some
#            captures were removed from gets the types the rest give it.
#   WORK     a directory for the work files (default: TYPES's own), so
#            none is left where a commit would take it up
# Returns 1, leaving TYPES as it was, if a file cannot be read or written.
_core_types_update () {
    local tf="$1" ds="$2" src="${3:-}" capid="${4:-}" work="${5:-}" old=/dev/null
    if [[ -n "$src" && -f "$tf" ]]; then old="$tf"; else src="$ds"; capid=""; fi
    [[ -f "$ds" && -f "$src" ]] || return 1
    [[ -n "$work" ]] || work="$(dirname "$tf")"
    local tmp="$work/.types.$$"
    if head -n 1 "$ds" > "$tmp.h" \
        && _TY_HDRF="$tmp.h" _TY_OLDF="$old" _core_types_awk record "$capid" "$tmp.h" "$old" "$src" > "$tmp"; then
        rm -f "$tmp.h"; mv "$tmp" "$tf"
    else
        rm -f "$tmp" "$tmp.h"; return 1
    fi
}

# _core_types_valid FILE — the file's own form, one finding a line on stdout
# (nothing when it is well formed): the header, six fields a line, a known
# type, the share, cells and counts as numbers that agree, each column once.
_core_types_valid () {
    LC_ALL=C awk -F'\t' -v HDR="$_CORE_TYPES_HDR" -v KINDS="$_CORE_TYPES_KINDS" '
        function bad(m) { if (nb++ < 3) print m }
        BEGIN { n = split(KINDS, K, " "); for (i = 1; i <= n; i++) { KN[K[i]] = 1; TN[K[i]] = 1 }
                TN["mixed"] = 1; TN["empty"] = 1 }
        NR == 1 { if ($0 != HDR) { print "its header is not column, type, share, cells, counts, set_by"; exit } next }
        NF != 6 { bad("line " NR ": " NF " fields, not 6"); next }
        ($1 in seen) { bad("column \"" $1 "\" is listed twice") }
        { seen[$1] = 1 }
        !($2 in TN) { bad("line " NR ": type \"" $2 "\" is not one provost records"); next }
        $4 !~ /^[0-9]+$/ { bad("line " NR ": cells \"" $4 "\" is not a count"); next }
        ($2 == "mixed" || $2 == "empty") && $3 != "" { bad("line " NR ": a " $2 " column has a share"); next }
        !($2 == "mixed" || $2 == "empty") && ($3 !~ /^[0-9]+$/ || $3 + 0 > 100) { bad("line " NR ": share \"" $3 "\" is not a per cent"); next }
        $2 == "empty" && ($4 != 0 || $5 != "") { bad("line " NR ": an empty column has cells"); next }
        $2 != "empty" && $4 == 0 { bad("line " NR ": a " $2 " column has no cells"); next }
        $6 != "" && $6 !~ /^c[0-9][0-9][0-9][0-9]+$/ { bad("line " NR ": set_by \"" $6 "\" is not a capture id"); next }
        {   s = 0; m = ($5 == "") ? 0 : split($5, p, ",")
            for (i = 1; i <= m; i++) {
                if (p[i] !~ /^[a-z]+=[0-9]+$/) { bad("line " NR ": counts \"" $5 "\" is not KIND=N,..."); next }
                k = p[i]; sub(/=.*/, "", k); v = p[i]; sub(/^[a-z]+=/, "", v)
                if (!(k in KN)) { bad("line " NR ": counts names \"" k "\", not a kind"); next }
                s += v
            }
            if (s != $4 + 0) bad("line " NR ": counts add up to " s ", cells is " $4)
        }' "$1"
}
