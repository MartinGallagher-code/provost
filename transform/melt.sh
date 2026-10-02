#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# provost/transform/melt.sh — the extract-output transform (tidy melt + schema-union
# helpers). First-party provost code; edit it here.
#
# Functions: _core_melt_tidy (+ _core_melt_tidy_file), _core_union_header,
# _core_align_rows.
# Originally imported from EnvoyCapture/lib/_core.sh
# @ 8639a6ef54fe5867aba8bee81171c5abd344adb3 (2026-07-05); maintained locally since.
#
# All three pass their arguments to awk through ENVIRON, never `awk -v`: -v
# processes backslash escapes, so a header or capture id holding `\t` or `\\`
# (a Windows path, a regex, a LaTeX name) would be silently rewritten — and a
# `\t` would even split one column name into two.

# The record prefixes the extract engine and its strategies use for a REPEATING
# RECORD, emitted as `<prefix><N>.<field>`: `entry` (the engine's canonical
# label — _helpers.sh, _dispatch.sh and ~600 strategy call sites) plus the
# handful of strategy-specific labels (fixed-width/pipe-table `row`,
# block-records `record`, line-records `line`, nmap `port`, exposition-format /
# openmetrics `metric`, beegfs `target`, docker-ps `container`, grafana-alerts
# `alert`, git-log `commit`, repeated-blocks `block`). Only these melt to an
# `n` index. Any other digit-suffixed key (`python3.version`, `eth0.mtu`,
# `TLSv1.2`) is an ordinary name — see _core_melt_tidy for how a family of them
# is handled. Keep this list in step with the strategies (grep
# `"<word>${n}.` under extract/strategies when adding a record label).
_CORE_MELT_RECORD_PREFIXES="entry row record line port metric target container alert commit block"

# Union of two TSV header lines, by column name: all of $1's columns in order,
# then any of $2's columns not already present. Prints the tab-joined header.
_core_union_header () {
    _MELT_OLD="$1" _MELT_NEW="$2" awk 'BEGIN{
        old=ENVIRON["_MELT_OLD"]; new=ENVIRON["_MELT_NEW"]
        n1=split(old,a,"\t"); n2=split(new,b,"\t"); m=0
        for(i=1;i<=n1;i++) if(!(a[i] in seen)){out[++m]=a[i]; seen[a[i]]=1}
        for(j=1;j<=n2;j++) if(!(b[j] in seen)){out[++m]=b[j]; seen[b[j]]=1}
        s=""; for(k=1;k<=m;k++) s=s (k>1?"\t":"") out[k]; print s
    }'
}

# Re-map data rows (read from stdin, no header) from a source header's column
# order to a target header's, matching by NAME and blanking columns the source
# lacks. Prints the aligned data rows (no header). This keeps a dataset
# rectangular across schema changes — added, removed, or reordered columns.
# A name repeated in the source header maps to its FIRST occurrence.
_core_align_rows () {
    _MELT_SH="$1" _MELT_TH="$2" awk -F'\t' -v OFS='\t' '
        BEGIN{
            ns=split(ENVIRON["_MELT_SH"],sc,"\t")
            for(i=1;i<=ns;i++) if(!(sc[i] in sidx)) sidx[sc[i]]=i
            nt=split(ENVIRON["_MELT_TH"],tc,"\t")
        }
        {
            line=""
            for(j=1;j<=nt;j++){ v=(tc[j] in sidx)?$(sidx[tc[j]]):""; line=line (j>1?OFS:"") v }
            print line
        }'
}

# Reshape a wide extract (header + one data row) into tidy long form when its
# columns are a repeating record group `<prefix><N>.<field>` whose prefix is one
# of the engine's record labels (_CORE_MELT_RECORD_PREFIXES; e.g.
# entry1.permissions, entry2.permissions, … as emitted by tar-listing /
# pipe-table). Emits one row per record, ordered by N (numerically), with a
# `capture` group id ($2, when given) and an `n` index, the record fields in
# first-seen order, then any other columns as scalars (repeated per row).
#
# A digit-suffixed name that is NOT a record label is a real name, not a
# counter: `python3.path`/`python3.version` stay two wide columns. When the
# input is instead one FAMILY of such names — a single stem with two or more
# members sharing a field, e.g. eth0.mtu/eth1.mtu — it is a keyed group: it
# melts to one row per member with a `key` column carrying the member's full
# name (eth0, eth1), so the interface name is kept as a value rather than being
# reduced to its number.
#
# The engine's record count, `total_entries N`, is per-capture metadata and not
# a variable: it is dropped (it would otherwise repeat on every row). In a
# melted table it is dropped only when N equals the number of records (anything
# else is not the count — e.g. a cell shifted there by a stray tab); in a
# pass-through snapshot, whenever N is an integer and not the only column.
#
# Anything that is NOT a single clean repeating group — plain scalars (`a b`),
# several record labels or families at once, a record group mixed with a
# digit-suffixed name, or anything other than exactly header + one row — is
# passed through (minus total_entries), so this only reshapes table-shaped
# output. Row order is by N, numerically and stably (entry2 before entry10).
#
# One exception: a single-column, single-row wide (one key/value observation —
# the shape of a version banner or one-line status) is emitted in long form
# (`field`/`value` columns), the canonical tidy layout for a lone observation
# of a lone variable. Multi-column snapshots keep their wide layout.
_core_melt_tidy () {
    local tsv="$1" capid="${2:-}"
    printf '%s\n' "$tsv" | _core_melt_tidy_stream "$capid"
}

# _core_melt_tidy_file FILE [capid] — exactly `_core_melt_tidy "$(cat FILE)"
# [capid]`, without pulling the file through a bash variable (for a 10 MB
# extract, the `$(cat)` capture plus the `printf` back out cost more than the
# melt itself). The pre-pass reproduces what that round trip does to the
# bytes: trailing newlines dropped, one newline added (so an empty or
# newline-only file is ONE empty line).
_core_melt_tidy_file () {
    awk '{ if ($0 == "") { pend++; next }
           for (; pend > 0; pend--) print ""
           print; seen = 1 }
         END { if (!seen) print "" }' "$1" | _core_melt_tidy_stream "${2:-}"
}

# The melt proper, as a stdin filter (shared by both entry points above).
_core_melt_tidy_stream () {
    local capid="${1:-}"
    _MELT_CAP="$capid" _MELT_RECS="$_CORE_MELT_RECORD_PREFIXES" \
        awk -F'\t' -v OFS='\t' '
        # Stable, O(n log n) bottom-up merge sort of IX[1..n] by the numeric
        # sort key KY[1..n] (kept in step with IX; both position-indexed, so
        # no per-comparison string-subscript conversions).
        function msort(n,    w, lo, mid, hi, i, j, k, t) {
          for (w = 1; w < n; w *= 2) {
            for (lo = 1; lo <= n - w; lo += 2 * w) {
              mid = lo + w - 1; hi = lo + 2 * w - 1; if (hi > n) hi = n
              if (KY[mid] <= KY[mid + 1]) continue          # runs already in order
              i = lo; j = mid + 1; k = 0
              while (i <= mid && j <= hi) {
                if (KY[j] < KY[i]) { TK[++k] = KY[j]; TI[k] = IX[j++] }
                else               { TK[++k] = KY[i]; TI[k] = IX[i++] }
              }
              while (i <= mid) { TK[++k] = KY[i]; TI[k] = IX[i++] }
              while (j <= hi)  { TK[++k] = KY[j]; TI[k] = IX[j++] }
              for (t = 1; t <= k; t++) { KY[lo + t - 1] = TK[t]; IX[lo + t - 1] = TI[t] }
            }
          }
        }
        function isint(s) { return s ~ /^[0-9]+$/ }
        BEGIN {
          cap = ENVIRON["_MELT_CAP"]
          nr = split(ENVIRON["_MELT_RECS"], rl, " "); for (i = 1; i <= nr; i++) REC[rl[i]] = 1
        }
        { L[NR] = $0 }
        # (split(), not a per-field copy loop: the same cells, but mawk keeps
        # a split() array as a flat vector — a 10 MB capture is ~1M columns)
        NR == 1 { nf = split($0, H, "\t") }
        NR == 2 { split($0, V, "\t") }
        END {
          if (NR != 2) { for (r = 1; r <= NR; r++) print L[r]; exit }  # only header+1row is meltable
          # total_entries: the engine record count (a bare integer) — metadata.
          for (i = 1; i <= nf; i++) if (H[i] == "total_entries" && isint(V[i])) DROP[i] = 1
          # NOTE: a data row wider than its header means a value held a TAB
          # that the engine emitted raw (extract/lib/_format.sh format_tsv);
          # the cells past it are misattributed and the surplus dropped. That
          # cannot be repaired here — which tab was the separator is lost — so
          # it must be fixed where the TSV is written.

          # Classify each column: record-group (r), digit-suffixed name (k), scalar.
          # (a record has adjacent columns that share their `<stem><N>`
          # prefix, so the prefix is classified once per run of it; NUM is
          # kept for the keyed kind only — a record id IS its number)
          nrs = 0; nks = 0; pleft = ""
          for (i = 1; i <= nf; i++) {
            h = H[i]; KIND[i] = ""; d = index(h, ".")
            if (d <= 1) continue
            left = substr(h, 1, d - 1)
            if (left != pleft) {
              pleft = left
              pok = match(left, /[0-9]+$/) && RSTART > 1
              if (pok) {
                stem = substr(left, 1, RSTART - 1); num = substr(left, RSTART) + 0
                prec = (stem in REC)
                if (prec) { if (!(stem in seenrs)) { seenrs[stem] = 1; nrs++ } }
                else if (!(stem in seenks)) { seenks[stem] = 1; nks++ }
              }
            }
            if (!pok) continue
            f = FLD[i] = substr(h, d + 1)
            # (the field names of each kind in first-seen order, collected here
            # rather than in a second pass over every column)
            if (prec) {
              KIND[i] = "r"; ID[i] = num
              if (!(f in SFR)) { SFR[f] = ++nfr; FLR[nfr] = f }
            } else {
              KIND[i] = "k"; ID[i] = left; NUM[i] = num
              if (!(f in SFK)) { SFK[f] = ++nfk; FLK[nfk] = f }
              # a field shared by two members makes this a repeating family
              if (!((left, FLD[i]) in seenlf)) {
                seenlf[left, FLD[i]] = 1
                if (++fcount[FLD[i]] >= 2) shared = 1
              }
            }
          }
          mode = ""
          if (nrs == 1 && nks == 0) mode = "r"
          else if (nrs == 0 && nks == 1 && shared) mode = "k"

          if (mode == "") {
            # lone key/value observation -> long form (see header comment)
            if (nf == 1 && H[1] != "" && V[1] != "") { print "field" OFS "value"; print H[1] OFS V[1]; exit }
            # not a single table: pass through verbatim, minus the record-count
            # metadata (unless that is the only column)
            ndrop = 0; for (i in DROP) ndrop++
            if (ndrop == 0 || ndrop >= nf) { print L[1]; print L[2]; exit }
            hs = ""; c = 0
            for (i = 1; i <= nf; i++) if (!(i in DROP)) { hs = hs (c ? OFS : "") H[i]; c++ }
            nd = split(L[2], D, "\t"); vs = ""; c = 0
            for (i = 1; i <= nd; i++) if (!(i in DROP)) { vs = vs (c ? OFS : "") D[i]; c++ }
            print hs; print vs; exit
          }

          nid = 0; nfld = 0; nsc = 0
          # Cells are keyed by POSITION (record ordinal x field ordinal), not
          # by an (id, field) string pair: mawk string-key hashing degrades
          # badly past ~1M keys, and a 10 MB capture has that many cells
          # (12 s for one melt). Same cells, same first-appearance orders.
          if (mode == "r") { nfld = nfr; for (k = 1; k <= nfld; k++) { FLDS[k] = FLR[k]; seenf[FLR[k]] = k } }
          else             { nfld = nfk; for (k = 1; k <= nfld; k++) { FLDS[k] = FLK[k]; seenf[FLK[k]] = k } }
          # (a record has its cells in adjacent columns: the row base is looked up
          # once per run of one id, not once per cell)
          lastid = ""; base = 0
          for (i = 1; i <= nf; i++) {
            if (KIND[i] == mode) {
              id = ID[i]
              if (id != lastid || i == 1) {
                if (!(id in seenid)) { seenid[id] = ++nid; IX[nid] = id; KY[nid] = (mode == "r") ? id : NUM[i] }
                base = (seenid[id] - 1) * nfld; lastid = id
              }
              CELL[base + seenf[FLD[i]]] = V[i]
            } else NSC[++nnsc] = i
          }
          # In a melted table total_entries is dropped only when it IS the record
          # count; any other value (a cell shifted into that column) is kept.
          for (c = 1; c <= nnsc; c++) {
            i = NSC[c]
            if (!((i in DROP) && V[i] + 0 == nid)) SC[++nsc] = i
          }
          # Order rows by N. Record ids are unique integers, nearly always a
          # dense 1..N run, so a presence scan over [min,max] is O(n); a sparse
          # or keyed set falls back to the stable merge sort.
          dense = 0
          if (mode == "r" && nid > 0) {
            lo = IX[1]; hi = IX[1]
            for (a = 2; a <= nid; a++) { if (IX[a] < lo) lo = IX[a]; if (IX[a] > hi) hi = IX[a] }
            if (hi - lo < 4 * nid + 64) {
              dense = 1; k = 0
              for (v = lo; v <= hi; v++) if (v in seenid) IX[++k] = v
            }
          }
          if (!dense) msort(nid)
          # The added index/capture columns must not duplicate the name of a data
          # column (valgrind-massif records carry their own `n`): a repeated name
          # breaks the by-name union/align. On a clash, prefix `_` until unique.
          for (k = 1; k <= nfld; k++) USED[FLDS[k]] = 1
          for (s = 1; s <= nsc; s++) USED[H[SC[s]]] = 1
          idcol = (mode == "r") ? "n" : "key"
          while (idcol in USED) idcol = "_" idcol
          USED[idcol] = 1; capcol = "capture"
          while (capcol in USED) capcol = "_" capcol
          hdr = (cap != "" ? capcol OFS : "") idcol
          for (k = 1; k <= nfld; k++) hdr = hdr OFS FLDS[k]
          for (s = 1; s <= nsc; s++) hdr = hdr OFS H[SC[s]]
          print hdr
          sc = ""; for (s = 1; s <= nsc; s++) sc = sc OFS V[SC[s]]
          pre = (cap != "" ? cap OFS : "")
          for (a = 1; a <= nid; a++) {
            id = IX[a]; row = pre id
            base = (seenid[id] - 1) * nfld
            for (k = 1; k <= nfld; k++) row = row OFS CELL[base + k]   # (a missing cell reads "")
            print row sc
          }
        }'
}
