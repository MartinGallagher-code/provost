#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: section-tables
## Description: Reports of several TITLED aligned tables (one per disk, chain, address family …) — one table with a `section` column
## Version: 1.0
## Priority: 36
## Confidence-Max: 82
## Sample: samples/section-tables/netstat-rn.txt

# A report that prints one aligned table per thing, each under its own title:
#
#   /dev/disk0 (internal, physical):          Chain INPUT (policy DROP …)
#      #:   TYPE NAME        SIZE  IDENT       pkts bytes target  prot …
#      0:   GUID_partition_… *500 GB disk0      1520  121K ACCEPT  all  …
#                                              (blank)
#   /dev/disk3 (synthesized):                 Chain FORWARD (policy …)
#      #:   TYPE NAME        SIZE  IDENT       pkts bytes target  prot …
#
# or, separated by rules, a few DIFFERENT tables (Windows `route print`: the
# interface list, then the IPv4 and IPv6 route tables under `====` rules and
# `Active Routes:` titles; `docker system df -v`; `ipcs`). A single-table
# parser reads the titles as rows and every later header as data, or a
# key/value parser glues each section into one cell (round-2 benchmark,
# pattern 2: diskutil, route print). Here every table row becomes one row of
# ONE table, its title path in a `section` column: tables that share their
# header are simply stacked; tables with different headers are unioned by
# column name (IPv4 and IPv6 routes share `Gateway` / `Metric`), each row
# keeping only its own cells. A line under a title that belongs to no table
# (`Persistent Routes:` / `None`, the headerless interface list) is kept as a
# row with its line in `text`, so nothing is dropped.
#
# Line roles (tabs expanded to 8 columns; a GUTTER is a run of 2+ blanks
# between two non-blank characters):
#   RULE    only `- = _ * ~ +` and blanks, 3+ rule characters: a separator;
#   TITLE   a TITLED rule (`------ Shared Memory Segments --------`, the text
#           kept), or an unindented line of at most 80 bytes without a gutter
#           (`IPv4 Route Table`, `Chain INPUT (policy DROP 0 packets, 0 bytes)`,
#           `Interface: 192.168.1.23 --- 0x6`), or one ending in `:` with no
#           more than one gutter (`Images space usage:`);
#   HEADER  the first other line of a section that has 3+ gutter-separated
#           cells (or 3+ words over a row of 3+ cells — two cells over
#           two-cell rows are `key   value` pairs), holds no number-only
#           token and no `Label: value` / `Label = value` pair, and is mostly
#           letters — its labels name the
#           columns; the lines below it up to a blank, a rule or a title are
#           its ROWS (a row may be empty-ish: an empty chain prints only its
#           header);
#   TEXT    anything else.
# Consecutive titles build a path (`IPv4 Route Table / Active Routes`); the
# first title after content starts a new one.
#
# Cells are placed by character OFFSET: each table goes through the gutter
# grid (_fr_gutter_grid, lib/_helpers.sh) first; when the grid withdraws, a
# label-span pass reads it — a header word over no data that is one blank
# from its neighbour joins it (`Network Destination`, `IMAGE ID`), a value
# goes to the label it overlaps most (else the nearest), values under one
# label join with a blank (`Local Fixed Disk`), and a row that only fills
# columns the row above left empty continues it (route print's wrapped IPv6
# destination). A table neither pass can place makes the whole input decline.
#
# Accepted when there are 2+ tables with rows, every table sits under a title,
# there are 2+ distinct titles, table rows outnumber TEXT rows, and fewer
# than 3 TEXT rows are `Label: value` pairs (a key/value section — smartctl's
# information block over its attribute table — is a report for the
# key/value and embedded-table parsers). Confidence
# 82 when every table has the same header (one layout repeated per section —
# the strongest evidence), else 80; priority 36 places it before
# embedded-table (37) and grouped-rows (41), which read one table or plain
# token rows.

# Segmentation. Prints the parsed structure, one record per line:
#   T<TAB>path<TAB>header      a table header (path = its title path)
#   R<TAB>row                  a row of the last table
#   X<TAB>path<TAB>text        a TEXT line
_ST_SEG_AWK='
function untab(s,    o, k, col) {
    o = ""; col = 0
    while ((k = index(s, "\t")) > 0) {
        o = o substr(s, 1, k - 1); col += k - 1
        do { o = o " "; col++ } while (col % 8)
        s = substr(s, k + 1)
    }
    return o s
}
function gutters(s,    t, g) {
    t = s; sub(/^ +/, "", t); g = 0
    while (match(t, /[^ ]   *[^ ]/)) { g++; t = substr(t, RSTART + RLENGTH - 1) }
    return g
}
function is_header(s,    t, n, i, w, a, num, alpha) {
    if (!gutters(s)) return 0
    t = s; sub(/^ +/, "", t)
    # a `Label : value` / `Label: value` / `Label = value` line is a
    # key/value pair, not a header (`#:` over diskutil'"'"'s rows names a
    # column, holding no letter)
    if (match(t, /:( |$)/) && substr(t, 1, RSTART) ~ /[A-Za-z]/) return 0
    if (t ~ / = /) return 0
    n = split(t, w, / +/); num = 0
    for (i = 1; i <= n; i++) {
        if (w[i] ~ /^[-+]?[0-9][0-9.,:%]*[A-Za-z]?$/) return 0
        if (w[i] ~ /[0-9]/) num++
    }
    a = t; alpha = gsub(/[A-Za-z]/, "", a)
    return (n >= 2 && num * 10 <= n * 3 && alpha * 2 >= length(t) - gsub(/ /, "", t))
}
# cells(s): gutter-separated cells of a line
function cells(s,    t, w) { t = s; sub(/^ +/, "", t); return split(t, w, /   */) }
# a header needs 3+ cells, or 3+ words over a row of 3+ cells: two cells
# over two-cell rows is a key/value block (`status   OK` over `pid   1184`)
# whose first pair would become the header
function header_at(i,    s, t, w, j) {
    s = L[i]
    if (!is_header(s)) return 0
    if (cells(s) >= 3) return 1
    t = s; sub(/^ +/, "", t)
    if (split(t, w, / +/) < 3) return 0
    for (j = i + 1; j <= n && L[j] == ""; j++) ;
    return (j <= n && cells(L[j]) >= 3)
}
function settitle(t) {
    if (content) { path = ""; content = 0 }
    path = (path == "" ? t : path " / " t)
}
# a line that can TITLE a section (see the header comment)
function titlish(s) {
    if (s ~ /^ / || length(s) > 80 || s ~ /^#( |$)/) return 0
    # a dashed group row (`procs ---memory--- ---swap--`) spans columns
    if (s ~ /---.*---/) return 0
    return (gutters(s) == 0 || (s ~ /:$/ && gutters(s) <= 1))
}
{ s = untab($0); sub(/\r$/, "", s); sub(/ +$/, "", s); L[++n] = s }
END {
    for (i = 1; i <= n; i++) {
        s = L[i]
        if (s == "") { intab = 0; continue }
        if (s ~ /^ *[-=_*~+][-=_*~+][-=_*~+]+[-=_*~+ ]*$/) { intab = 0; continue }
        if (s ~ /^ *[-=][-=][-=]+ +[^ ].* +[-=][-=][-=]+ *$/) {
            t = s; sub(/^ *[-=]+ +/, "", t); sub(/ +[-=]+ *$/, "", t)
            intab = 0; settitle(t); continue
        }
        if (titlish(s) && (!intab || s ~ /:$/)) {
            # a `Label: value` line titles only the table right below it
            # (`Interface: 10.0.0.5 --- 0x6`); elsewhere it is a pair
            kv = (match(s, /: /) && substr(s, 1, RSTART) ~ /[A-Za-z]/)
            for (j = i + 1; j <= n && L[j] == ""; j++) ;
            if (!kv || (j <= n && header_at(j))) {
                t = s; sub(/:$/, "", t)
                intab = 0; settitle(t); continue
            }
        }
        if (intab) { print "R\t" s; continue }
        # (a `# col  col` comment header is the chrome of a commented report)
        if (s !~ /^ *#( |$)/ && header_at(i)) { print "T\t" path "\t" s; intab = 1; content = 1; continue }
        print "X\t" path "\t" s; content = 1
    }
}'

# Label-span pass for one table (header + rows on stdin, tabs expanded; a
# `\001<id>` line marks where the rows of section <id> start, when several
# same-header tables are read as one). Prints `entry<N>.<label> <value>`
# lines (and `entry<N>.\001 <id>` for a marked row) and `total_entries N`, or
# nothing.
_ST_SPAN_AWK='
function tok(s, r,    p, q, k) {
    k = 0; p = 1
    while (match(substr(s, p), /[^ ]+/)) {
        q = p + RSTART - 1; k++
        TS[r, k] = q; TE[r, k] = q + RLENGTH - 1; TX[r, k] = substr(s, q, RLENGTH)
        p = q + RLENGTH
    }
    NT[r] = k
}
function ov(a1, b1, a2, b2,    lo, hi) {
    lo = (a1 > a2 ? a1 : a2); hi = (b1 < b2 ? b1 : b2)
    return hi >= lo ? hi - lo + 1 : 0
}
/^\001/ { sec = substr($0, 2); next }
{ L[++n] = $0; tok($0, n); SEC[n] = sec }
END {
    if (n < 2) exit
    nh = NT[1]
    if (nh < 2) exit
    # data over each header word; a value spanning two single-spaced words
    # binds them into one label
    for (r = 2; r <= n; r++) for (k = 1; k <= NT[r]; k++) {
        hit = 0
        for (j = 1; j <= nh; j++) if (ov(TS[r, k], TE[r, k], TS[1, j], TE[1, j])) {
            OV[j]++; if (hit && TS[1, j] == TE[1, hit] + 2) BIND[hit] = 1
            hit = j
        }
    }
    # a data-free word one blank from a neighbour joins it (right first)
    for (j = 1; j <= nh; j++) {
        if (OV[j]) continue
        if (j < nh && TS[1, j + 1] == TE[1, j] + 2) BIND[j] = 1
        else if (j > 1 && TS[1, j] == TE[1, j - 1] + 2) BIND[j - 1] = 1
    }
    ng = 0
    for (j = 1; j <= nh; j++) {
        if (j == 1 || !BIND[j - 1]) { ng++; GS[ng] = TS[1, j]; GN[ng] = TX[1, j] }
        else GN[ng] = GN[ng] " " TX[1, j]
        GE[ng] = TE[1, j]
    }
    if (ng < 2) exit
    for (g = 1; g <= ng; g++) {
        nm = GN[g]; gsub(/ /, "_", nm)
        if (nm in SEEN) { SEEN[nm]++; nm = nm "_" SEEN[nm] } else SEEN[nm] = 1
        NM[g] = nm
    }
    ne = 0; tot = 0; hitc = 0
    for (r = 2; r <= n; r++) {
        if (!NT[r]) continue
        for (g = 1; g <= ng; g++) C[g] = ""
        first = 0
        for (k = 1; k <= NT[r]; k++) {
            best = 0; bo = 0
            for (g = 1; g <= ng; g++) { o = ov(TS[r, k], TE[r, k], GS[g], GE[g]); if (o > bo) { bo = o; best = g } }
            tot++
            if (best) hitc++
            else {
                bd = -1
                for (g = 1; g <= ng; g++) {
                    d = (TS[r, k] > GE[g] ? TS[r, k] - GE[g] : GS[g] - TE[r, k])
                    if (bd < 0 || d < bd) { bd = d; best = g }
                }
            }
            C[best] = (C[best] == "" ? TX[r, k] : C[best] " " TX[r, k])
            if (!first) first = best
        }
        # a row that only fills columns the row above left empty continues it
        cont = 0
        if (ne && first > 1 && SEC[r] == OSEC[ne]) {
            cont = 1
            for (g = 1; g <= ng; g++) if (C[g] != "" && OUT[ne, g] != "") cont = 0
        }
        if (!cont) { ne++; OSEC[ne] = SEC[r] }
        for (g = 1; g <= ng; g++) if (C[g] != "") OUT[ne, g] = C[g]
    }
    # values must sit under their labels: most tokens overlap one
    if (tot && hitc * 10 < tot * 7) exit
    for (i = 1; i <= ne; i++) {
        if (OSEC[i] != "") printf "entry%d.\001 %s\n", i, OSEC[i]
        for (g = 1; g <= ng; g++)
            if (OUT[i, g] != "") printf "entry%d.%s %s\n", i, NM[g], OUT[i, g]
    }
    printf "total_entries %d\n", ne
}'

# _st_parse TEXT — runs the segmentation and parses every table. Sets
# _ST_OUT (the field lines, records numbered from 1), _ST_NT (tables with
# rows), _ST_NTAB (all tables), _ST_ROWS, _ST_TEXT (TEXT rows), _ST_SAME (1
# when every table has the same labels), _ST_TITLES (distinct titles).
# Returns 1 when the shape is not there or a table cannot be placed.
# Tables printed with the same header LINE (same labels, same offsets) are
# read TOGETHER — one grid over all their rows (kept only when it returns one
# record per row, so each row's section is known), else one label-span pass
# with section marks — so every section gets the same columns; any other
# header is read on its own (netstat -rn pads its IPv6 table wider).
_st_parse () {
    _ST_OUT=""; _ST_NT=0; _ST_NTAB=0; _ST_ROWS=0; _ST_TEXT=0; _ST_SAME=1; _ST_TITLES=0; _ST_KV=0
    local _seg _l _kind _rest _t=0 _k _lab
    local -a _tp=() _th=() _tl=() _tr=() _ord=()
    local -A _st_titles=() _rows=()
    _seg="$(printf '%s\n' "$1" | LC_ALL=C awk "$_ST_SEG_AWK")"
    [[ "$_seg" == *T$'\t'* ]] || return 1
    # 1. collect: tables (path, header, label key, rows) and TEXT rows, in order
    while IFS= read -r _l; do
        _kind="${_l%%$'\t'*}"; _rest="${_l#*$'\t'}"
        case "$_kind" in
            T)  _t=$((_t + 1)); _tp[$_t]="${_rest%%$'\t'*}"; _th[$_t]="${_rest#*$'\t'}"
                [[ -n "${_tp[$_t]}" ]] || return 1
                _st_titles[${_tp[$_t]}]=1
                _lab="${_th[$_t]}"; while [[ "$_lab" == *"  "* ]]; do _lab="${_lab//  / }"; done
                _tl[$_t]="${_lab# }"; _tr[$_t]=0
                [[ "${_tl[$_t]}" != "${_tl[1]}" ]] && _ST_SAME=0
                _ord+=("T$_t") ;;
            R)  _tr[$_t]=$(( ${_tr[$_t]} + 1 )); _rows[$_t,${_tr[$_t]}]="$_rest" ;;
            X)  _ord+=("X$_rest")
                [[ -n "${_rest%%$'\t'*}" ]] && _st_titles[${_rest%%$'\t'*}]=1 ;;
        esac
    done <<< "$_seg"
    _ST_NTAB=$_t; _ST_TITLES=${#_st_titles[@]}
    # 2. parse each group of same-header tables
    local -A _rec=() _done=()
    local _i _j _r _in _g _n _sec _f _cnt _tot
    for ((_i = 1; _i <= _t; _i++)); do
        [[ -n "${_done[$_i]:-}" ]] && continue
        local -a _grp=()
        for ((_j = _i; _j <= _t; _j++)); do
            [[ "${_th[$_j]}" == "${_th[$_i]}" ]] && { _grp+=("$_j"); _done[$_j]=1; }
        done
        _tot=0; for _j in "${_grp[@]}"; do _tot=$((_tot + ${_tr[$_j]})); done
        [[ $_tot -gt 0 ]] || continue
        # (a) the grid over all the group's rows (header of the first table)
        _in="${_th[$_i]}"$'\n'
        for _j in "${_grp[@]}"; do
            for ((_r = 1; _r <= ${_tr[$_j]}; _r++)); do _in+="${_rows[$_j,$_r]}"$'\n'; done
        done
        _g="$(printf '%s' "$_in" | _fr_gutter_grid 1 0 st)"
        if [[ -n "$_g" && "$_g" == *$'\n'"total_entries $_tot" ]]; then
            # one record per row: rows map to sections by order
            local -a _secof=()
            for _j in "${_grp[@]}"; do
                for ((_r = 1; _r <= ${_tr[$_j]}; _r++)); do _secof+=("$_j"); done
            done
            while IFS= read -r _l; do
                [[ "$_l" == st[0-9]*.* ]] || continue
                _n="${_l%%.*}"; _n="${_n#st}"; _sec="${_secof[$((_n - 1))]}"
                _rec[$_sec]+="${_n}.${_l#*.}"$'\n'
            done <<< "$_g"
        else
            # (b) the label-span pass, rows marked with their table
            _in="${_th[$_i]}"$'\n'
            for _j in "${_grp[@]}"; do
                _in+=$'\001'"$_j"$'\n'
                for ((_r = 1; _r <= ${_tr[$_j]}; _r++)); do _in+="${_rows[$_j,$_r]}"$'\n'; done
            done
            _g="$(printf '%s' "$_in" | LC_ALL=C awk "$_ST_SPAN_AWK")"
            [[ -n "$_g" ]] || return 1
            local -A _secn=()
            while IFS= read -r _l; do
                [[ "$_l" == entry[0-9]*.* ]] || continue
                _n="${_l%%.*}"; _n="${_n#entry}"; _f="${_l#*.}"
                if [[ "$_f" == $'\001 '* ]]; then _secn[$_n]="${_f#$'\001 '}"; continue; fi
                _rec[${_secn[$_n]}]+="${_n}.${_f}"$'\n'
            done <<< "$_g"
        fi
    done
    # 2b. one layout, one set of columns: when the sections share their
    # labels but were padded differently, the grid may join a data-free
    # label to its neighbour in one of them (`Netif Expire` -> `Netif_Expire`
    # under netstat -rn's IPv6 table, `Netif` / `Expire` under IPv4) — such a
    # joined name whose parts are names elsewhere takes its first part
    if [[ $_ST_SAME -eq 1 ]]; then
        local -A _names=()
        for _j in "${!_rec[@]}"; do
            while IFS= read -r _l; do
                [[ -n "$_l" ]] || continue
                _f="${_l#*.}"; _names[${_f%% *}]=1
            done <<< "${_rec[$_j]}"
        done
        local _nm _pp _ok _fix=""
        for _nm in "${!_names[@]}"; do
            [[ "$_nm" == *_* ]] || continue
            _ok=1
            for _pp in ${_nm//_/ }; do [[ -n "${_names[$_pp]:-}" ]] || { _ok=0; break; }; done
            [[ $_ok -eq 1 ]] && _fix+="${_nm} ${_nm%%_*}"$'\n'
        done
        if [[ -n "$_fix" ]]; then
            for _j in "${!_rec[@]}"; do
                _rec[$_j]="$(printf '%s' "${_rec[$_j]}" | awk -v fx="$_fix" '
                    BEGIN { m = split(fx, A, "\n"); for (i = 1; i <= m; i++) if (A[i] != "") { split(A[i], P, " "); R[P[1]] = P[2] } }
                    { d = index($0, "."); f = substr($0, d + 1); k = f; sub(/ .*/, "", k)
                      if (k in R) $0 = substr($0, 1, d) R[k] substr(f, length(k) + 1)
                      print }')"$'\n'
            done
        fi
    fi
    # 3. emit in document order, records renumbered from 1
    local _e=0 _o _p _x
    for _o in "${_ord[@]}"; do
        if [[ "$_o" == T* ]]; then
            _j="${_o#T}"
            [[ -n "${_rec[$_j]:-}" ]] || continue
            _ST_NT=$((_ST_NT + 1))
            # (the grid may emit column by column: gather each record's
            # cells, then emit the records in row order)
            local -A _cells=()
            local -a _nums=()
            while IFS= read -r _l; do
                [[ -n "$_l" ]] || continue
                _n="${_l%%.*}"
                [[ -n "${_cells[$_n]+x}" ]] || _nums+=("$_n")
                _cells[$_n]+="${_l#*.}"$'\n'
            done <<< "${_rec[$_j]}"
            while IFS= read -r _n; do
                _e=$((_e + 1)); _ST_ROWS=$((_ST_ROWS + 1))
                _ST_OUT+="entry${_e}.section ${_tp[$_j]}"$'\n'
                while IFS= read -r _l; do
                    [[ -n "$_l" ]] && _ST_OUT+="entry${_e}.${_l}"$'\n'
                done <<< "${_cells[$_n]}"
            done < <(printf '%s\n' "${_nums[@]}" | sort -n)
            unset _cells _nums
        else
            _x="${_o#X}"; _p="${_x%%$'\t'*}"; _x="${_x#*$'\t'}"
            _x="${_x#"${_x%%[![:space:]]*}"}"
            _e=$((_e + 1)); _ST_TEXT=$((_ST_TEXT + 1))
            [[ "$_x" =~ ^[A-Za-z][^:]{0,40}:[[:space:]]+[^[:space:]] ]] && _ST_KV=$((_ST_KV + 1))
            [[ -n "$_p" ]] && _ST_OUT+="entry${_e}.section ${_p}"$'\n'
            _ST_OUT+="entry${_e}.text ${_x}"$'\n'
        fi
    done
    _ST_OUT+="total_entries ${_e}"$'\n'
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # PREFILTER (exact): a table needs a gutter somewhere
    [[ "$text" == *[![:space:]]"  "*[![:space:]]* ]] || return 1
    _st_parse "$text" || return 1
    [[ $_ST_NT -ge 2 && $_ST_TITLES -ge 2 && $_ST_ROWS -gt $_ST_TEXT && $_ST_KV -lt 3 ]] || return 1
    if [[ $_ST_SAME -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=82
        _STRATEGY_CONFIDENCE_REASON="$_ST_NTAB titled tables with one header"
    else
        _STRATEGY_CONFIDENCE=80
        _STRATEGY_CONFIDENCE_REASON="$_ST_NTAB titled tables"
    fi
    return 0
}

strategy_extract () {
    _st_parse "$1" || return 0
    printf '%s' "$_ST_OUT"
}
