# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# provost_pseudo.awk -- host names and addresses to stable pseudonyms, for
# 'provost export --redact POLICY' (PV-033). Loaded after
# provost_redact.awk, whose scrub() also runs on everything exported.
#
# Where a name can be. A RUN is a stretch of letters, digits and . _ : - ;
# inside a run, a CANDIDATE is any part that starts at the run's start or
# just after one of . _ : - and ends at the run's end or just before one. So
# in "web03.example.com:22" the candidates include web03, example.com,
# web03.example.com and 22; in "node7-ib0", node7 and ib0. A run is rewritten
# left to right, taking at each start the LONGEST candidate the map holds.
#
# What a name is (MODE=collect, from the policy):
#   ip4    four dotted numbers 0-255, not next to another dotted number
#          (1.3.6.1.2.1 is not two addresses); not 0.0.0.0, 127.x.x.x or a
#          netmask (255.255.255.0)
#   ip6    an IPv6 address, :: and embedded IPv4 included; not :: or ::1
#   host   a name in one of the policy's domains, or matching one of its host
#          patterns (lower-cased first); every value in a dataset column the
#          policy names; every line of a hosts file
# A host name has a letter in it, and is never a capture id (c0007). A host
# name with dots whose first label has a letter and a digit in it gives that
# label too (web03 from web03.example.com: outputs often print the short
# name); not a label without a digit, so www, mail and api stay words.
#
# Modes (all under LC_ALL=C):
#   collect   stdin: git cat-file --batch output of every blob; also reads
#             STREAM (the fast-export stream: commit messages and paths) and
#             HOSTS (hosts-file lines). Prints "kind<TAB>name" for every name
#             found, unsorted, repeats included; the capture ids of the
#             'unsorted' dataset's rows go to HELD.
#   blobs     stdin: git cat-file --batch output; each blob is scrubbed and
#             pseudonymised into OUTDIR/<its sha>. With META=1 the blobs are
#             meta.tsv files: the input hash goes, output_sha256 becomes the
#             one in OUT256 ("id<TAB>sha256"), and "pseudonymised" is added.
#             With UNSORTED=1 they are the 'unsorted' dataset, whose raw
#             column is base64 of the capture's input -- of its output.txt --
#             and becomes the base64 in B64F ("id<TAB>base64"; RAWGONE when
#             the row has no capture id).
#   stream    stdin: the fast-export stream; blob ids from GITMAP ("old<TAB>
#             new"), dataset paths and messages rewritten, Input-SHA256
#             and Operator trailers dropped and Output-SHA256 ones taken
#             from OUT256.
# MAP ("kind<TAB>name<TAB>pseudonym") is read by blobs and stream. USED gets
# "kind<TAB>name" for each name replaced; COUNTS the secret counts.
# Policy, from the environment: RP_IPV4, RP_IPV6 (1/0), RP_DOMAINS,
# RP_HOSTRES, RP_COLS (newline-separated lists); RP_KEYID.

function pseudo_init(    n, i, a) {
    if (_PS_INIT) return
    _PS_INIT = 1
    SEPS = "._:-"
    IPV4 = (ENVIRON["RP_IPV4"] != "0"); IPV6 = (ENVIRON["RP_IPV6"] != "0")
    NDOM = 0; n = split(ENVIRON["RP_DOMAINS"], a, "\n")
    for (i = 1; i <= n; i++) if (a[i] != "") DOM[++NDOM] = tolower(a[i])
    NHRE = 0; n = split(ENVIRON["RP_HOSTRES"], a, "\n")
    for (i = 1; i <= n; i++) if (a[i] != "") HRE[++NHRE] = "^(" tolower(a[i]) ")$"
    n = split(ENVIRON["RP_COLS"], a, "\n")
    for (i = 1; i <= n; i++) if (a[i] != "") COLSET[tolower(a[i])] = 1
    if (MAP != "") {
        while ((getline a[0] < MAP) > 0) { split(a[0], a, "\t"); PM[a[1] SUBSEP a[2]] = a[3] }
        close(MAP)
    }
}

# --- what a name is ---------------------------------------------------------
# ip4norm(C): "a.b.c.d" without leading zeros, or "" when C is not one.
function ip4norm(c,    n, P, i) {
    if (c !~ /^[0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*$/) return ""
    n = split(c, P, ".")
    for (i = 1; i <= 4; i++) if (length(P[i]) > 3 || P[i] + 0 > 255) return ""
    return (P[1] + 0) "." (P[2] + 0) "." (P[3] + 0) "." (P[4] + 0)
}
# Addresses that say nothing about a site: any, loopback, broadcast, masks.
function ip4special(n,    P, i, seen) {
    split(n, P, ".")
    if (P[1] == 127) return 1
    seen = 0                       # a netmask: 255s, then one of these, then 0s
    for (i = 1; i <= 4; i++) {
        if (seen) { if (P[i] != 0) return 0; continue }
        if (P[i] == 255) continue
        if (P[i] !~ /^(0|128|192|224|240|248|252|254)$/) return 0
        seen = 1
    }
    return 1
}
# ip6norm(C): C (lower case) as eight 4-digit groups, or "" when not IPv6.
function ip6norm(c,    v4, k, P, dc, left, right, nl, nr, L, R, G, n, i, out) {
    if (c !~ /^[0-9a-f:.]+$/ || index(c, ":") == 0) return ""
    if (index(c, ".")) {            # a trailing dotted IPv4 part: two groups
        k = c; sub(/.*:/, "", k)
        v4 = ip4norm(k); if (v4 == "") return ""
        split(v4, P, ".")
        c = substr(c, 1, length(c) - length(k)) sprintf("%02x%02x:%02x%02x", P[1], P[2], P[3], P[4])
    }
    dc = index(c, "::")
    n = 0
    if (dc) {
        if (index(substr(c, dc + 1), "::")) return ""
        left = substr(c, 1, dc - 1); right = substr(c, dc + 2)
        nl = (left == "") ? 0 : split(left, L, ":")
        nr = (right == "") ? 0 : split(right, R, ":")
        if (nl + nr > 7) return ""
        for (i = 1; i <= nl; i++) G[++n] = L[i]
        for (i = 1; i <= 8 - nl - nr; i++) G[++n] = "0"
        for (i = 1; i <= nr; i++) G[++n] = R[i]
    } else {
        n = split(c, G, ":")
        if (n != 8) return ""
    }
    out = ""
    for (i = 1; i <= 8; i++) {
        if (G[i] !~ /^[0-9a-f][0-9a-f]*$/ || length(G[i]) > 4) return ""
        out = out (i > 1 ? ":" : "") substr("0000", length(G[i]) + 1) G[i]
    }
    return out
}
function ip6special(n) {
    return (n == "0000:0000:0000:0000:0000:0000:0000:0000" || n == "0000:0000:0000:0000:0000:0000:0000:0001")
}
# hostok(LC): LC could be a host name.
function hostok(lc) {
    if (lc !~ /^[a-z0-9_]([a-z0-9_.-]*[a-z0-9_])?$/) return 0
    if (lc !~ /[a-z]/ || index(lc, "..")) return 0
    if (lc ~ /^c[0-9][0-9][0-9][0-9][0-9]*$/) return 0
    return 1
}
# The context an address needs: no '.' right before it, and none right after
# it unless that '.' ends the run (a full stop).
function ip4ctx(r, s, e, L) {
    if (s > 1 && substr(r, s - 1, 1) == ".") return 0
    if (e < L && substr(r, e + 1, 1) == "." && e + 1 < L) return 0
    return 1
}

# classify(C, CTX): by the policy's rules. Sets CK (kind) and CN (name).
function classify(c, ctx,    n, lc, i, d) {
    if (c ~ /^[0-9.]+$/) {
        if (!IPV4 || !ctx) return 0
        n = ip4norm(c); if (n == "" || ip4special(n)) return 0
        CK = "ip4"; CN = n; return 1
    }
    if (index(c, ":")) {
        if (!IPV6) return 0
        n = ip6norm(tolower(c)); if (n == "" || ip6special(n)) return 0
        CK = "ip6"; CN = n; return 1
    }
    lc = tolower(c)
    if (!hostok(lc)) return 0
    for (i = 1; i <= NDOM; i++) {
        d = DOM[i]
        if (lc == d) { CK = "host"; CN = lc; CSELF = 1; return 1 }
        if (length(lc) > length(d) + 1 && substr(lc, length(lc) - length(d)) == "." d) { CK = "host"; CN = lc; CSELF = 0; return 1 }
    }
    for (i = 1; i <= NHRE; i++) if (lc ~ HRE[i]) { CK = "host"; CN = lc; CSELF = 0; return 1 }
    return 0
}
# A host name's short form: its first label, when that has a letter and a
# digit in it (web03 from web03.example.com; not www from www.example.com).
function emit_short(n,    i, l) {
    i = index(n, "."); if (!i) return
    l = substr(n, 1, i - 1)
    if (l ~ /[a-z]/ && l ~ /[0-9]/ && hostok(l)) print "host\t" l
}
# A name given outright (a hosts-file line, a column's value).
function add_name(v,    lc, n) {
    gsub(/^[ \t]+|[ \t]+$/, "", v)
    lc = tolower(v)
    if (length(lc) < 2) return
    if ((n = ip4norm(lc)) != "") { if (!ip4special(n)) print "ip4\t" n; return }
    if (index(lc, ":") && (n = ip6norm(lc)) != "") { if (!ip6special(n)) print "ip6\t" n; return }
    if (!hostok(lc)) return
    if (lc ~ /^(none|null|nil|unknown|localhost|n\/a|na|any|all|default|undefined|true|false|yes|no)$/) return
    print "host\t" lc
    emit_short(lc)
}
# lookup(C, CTX): the pseudonym the map holds for candidate C, or "".
function lookup(c, ctx,    n) {
    if (c ~ /^[0-9.]+$/) {
        if (!ctx) return ""
        n = ip4norm(c); if (n == "") return ""
        if (("ip4" SUBSEP n) in PM) { LK = "ip4"; LN = n; return PM["ip4" SUBSEP n] }
        return ""
    }
    if (index(c, ":")) {
        n = ip6norm(tolower(c)); if (n == "") return ""
        if (("ip6" SUBSEP n) in PM) { LK = "ip6"; LN = n; return PM["ip6" SUBSEP n] }
        return ""
    }
    n = tolower(c)
    if (("host" SUBSEP n) in PM) { LK = "host"; LN = n; return PM["host" SUBSEP n] }
    return ""
}

# --- runs and candidates ----------------------------------------------------
# _bounds(R): the starts (BS[1..NS]) and ends (BE[1..NE]) of R's candidates.
function _bounds(r,    L, i) {
    L = length(r); NS = 0; NE = 0
    for (i = 1; i <= L; i++) {
        if (i == 1 || index(SEPS, substr(r, i - 1, 1))) BS[++NS] = i
        if (i == L || index(SEPS, substr(r, i + 1, 1))) BE[++NE] = i
    }
}
# collect_run(R): print every candidate of R the rules call a name.
function collect_run(r,    L, i, j, s, e) {
    L = length(r)
    if (L < 2) return
    _bounds(r)
    for (i = 1; i <= NS; i++) {
        s = BS[i]
        for (j = NE; j >= 1; j--) {
            e = BE[j]; if (e < s) break
            if (e - s + 1 > 253) continue
            if (classify(substr(r, s, e - s + 1), ip4ctx(r, s, e, L))) {
                print CK "\t" CN
                if (CK == "host" && !CSELF) emit_short(CN)
            }
        }
    }
}
# pseudo_run(R): R with the longest mapped candidate at each start replaced.
function pseudo_run(r,    L, out, pos, i, j, s, e, rep) {
    L = length(r)
    if (L < 2) return r
    _bounds(r)
    out = ""; pos = 1
    for (i = 1; i <= NS; i++) {
        s = BS[i]; if (s < pos) continue
        rep = ""
        for (j = NE; j >= 1; j--) {
            e = BE[j]; if (e < s) break
            if (e - s + 1 > 253) continue
            rep = lookup(substr(r, s, e - s + 1), ip4ctx(r, s, e, L))
            if (rep != "") break
        }
        if (rep != "") {
            out = out substr(r, pos, s - pos) rep; pos = e + 1
            if (USED != "" && !((LK SUBSEP LN) in UL)) { UL[LK SUBSEP LN] = 1; print LK "\t" LN > USED }
        }
    }
    return out substr(r, pos)
}
# _runs(S): S split into its runs (RUN[1..NR]) and the gaps around them
# (GAP[1..NR+1]), in linear time: S = GAP[1] RUN[1] GAP[2] ... RUN[NR] GAP[NR+1].
function _runs(s,    n, T, i) {
    NR_ = 0
    if (s == "") { GAP[1] = ""; return }
    n = split(s, GAP, /[A-Za-z0-9_.:-]+/)
    split(s, T, /[^A-Za-z0-9_.:-]+/)
    for (i = 1; i in T; i++) if (T[i] != "") RUN[++NR_] = T[i]
    if (n != NR_ + 1) { GAP[1] = s; NR_ = 0 }     # (cannot happen; keep S whole)
}
function pseudo(s,    i, out) {
    _runs(s)
    if (NR_ == 0) return s
    out = GAP[1]
    for (i = 1; i <= NR_; i++) out = out pseudo_run(RUN[i]) GAP[i + 1]
    return out
}
function collect(s,    i) {
    _runs(s)
    for (i = 1; i <= NR_; i++) collect_run(RUN[i])
}
# A line as exported: secrets scrubbed, then names replaced. PS_DROP is set
# when the line goes (inside a private key block).
function export_line(l) {
    l = scrub_line(l); PS_DROP = SCRUB_DROP
    return PS_DROP ? "" : pseudo(l)
}

# --- git cat-file --batch -------------------------------------------------
# Calls blob_begin(SHA), blob_line(LINE) for each line, blob_end(ENDS_LF).
function read_batch(    hdr, H, sha, size, got, line, ends_lf) {
    while ((getline hdr) > 0) {
        if (split(hdr, H, " ") != 3) continue            # "<sha> missing"
        sha = H[1]; size = H[3] + 0
        blob_begin(sha)
        got = 0; ends_lf = 1
        while (got < size) {
            if ((getline line) <= 0) break
            got += length(line) + 1
            if (got > size) ends_lf = 0                  # its last line had no LF
            blob_line(line)
        }
        if (ends_lf) getline line                        # the LF after the blob
        blob_end(ends_lf)
    }
}

function blob_begin(sha) {
    BSHA = sha; BLN = 0; BHDR = -1; HAVE_PREV = 0; scrub_reset()
    if (MODE == "collect") { BCOLS = 0; if (sha in DSBLOB) BHDR = 1; BHELD = (sha in HELDBLOB) }
    else { BOUT = OUTDIR "/" sha; printf "" > BOUT }
}
function blob_line(line,    n, F, i, k, v) {
    BLN++
    if (MODE == "collect") {
        if (BHELD) {                               # 'unsorted': its rows' capture ids
            n = split(line, F, "\t")
            if (BLN == 1) { HCAP = 0; for (i = 1; i <= n; i++) if (F[i] == "capture") HCAP = i }
            else if (HCAP && F[HCAP] ~ /^c[0-9]+$/ && HELD != "") print F[HCAP] > HELD
            return                                 # (its raw column is the capture's output.txt, read anyway)
        }
        collect(line)
        if (BHDR == 1 && BLN == 1) {               # a dataset's header: its host columns
            n = split(line, F, "\t")
            for (i = 1; i <= n; i++) if (tolower(F[i]) in COLSET) BCOL[++BCOLS] = i
            if (!BCOLS) BHDR = -1
        } else if (BHDR == 1 && BCOLS) {
            split(line, F, "\t")
            for (i = 1; i <= BCOLS; i++) add_name(F[BCOL[i]])
        }
        return
    }
    if (UNSORTED) {
        n = split(line, F, "\t")
        if (BLN == 1) { URAW = 0; UCAP = 0; for (i = 1; i <= n; i++) { if (F[i] == "raw") URAW = i; if (F[i] == "capture") UCAP = i } }
        v = ""
        for (i = 1; i <= n; i++) {
            if (BLN > 1 && i == URAW) k = (UCAP && (F[UCAP] in B64)) ? B64[F[UCAP]] : RAWGONE
            else k = export_line(F[i])
            v = v (i > 1 ? "\t" : "") k
        }
        line = v
    } else if (META) {
        n = index(line, "\t"); k = n ? substr(line, 1, n - 1) : line
        if (k == "input_sha256" || k == "input_bytes") return
        if (k == "id") MID = substr(line, n + 1)
        if (k == "output_sha256") { if (!(MID in OUT256)) return; line = k "\t" OUT256[MID] }
        else if (n) { v = export_line(substr(line, n + 1)); line = k "\t" v }
    } else {
        line = export_line(line)
        if (PS_DROP) return
    }
    if (HAVE_PREV) printf "%s\n", PREV > BOUT
    PREV = line; HAVE_PREV = 1
}
function blob_end(ends_lf) {
    if (MODE == "collect") return
    if (META) {
        if (HAVE_PREV) printf "%s\n", PREV > BOUT
        printf "pseudonymised\tkey %s\n", ENVIRON["RP_KEYID"] > BOUT
    } else if (HAVE_PREV) {
        printf (ends_lf ? "%s\n" : "%s"), PREV > BOUT
    }
    close(BOUT)
}

# --- the fast-export stream -------------------------------------------------
function tpath(p,    name, np) {
    if (p !~ /^datasets\/.*[.]tsv$/) return p
    name = substr(p, 10, length(p) - 13)
    np = "datasets/" pseudo(name) ".tsv"
    if ((np in NEWPATH) && NEWPATH[np] != p) {
        printf "provost: %s and %s would both be exported as %s\n", NEWPATH[np], p, np > "/dev/stderr"
        exit 3
    }
    NEWPATH[np] = p
    return np
}
function fixmsg(msg,    n, L, i, out, l, F, ends, insig) {
    ends = (substr(msg, length(msg)) == "\n")
    if (ends) msg = substr(msg, 1, length(msg) - 1)
    n = split(msg, L, "\n")
    out = ""; scrub_reset(); insig = 0
    for (i = 1; i <= n; i++) {
        l = L[i]
        # a signed tag's signature (git fast-export strips only OpenPGP
        # ones, and none would verify on the rewritten history): dropped
        if (l ~ /^-----BEGIN (SSH|PGP) SIGNATURE-----$/) { insig = 1; continue }
        if (insig) { if (l ~ /^-----END (SSH|PGP) SIGNATURE-----$/) insig = 0; continue }
        if (l ~ /^Input-SHA256: /) continue
        # who made the capture (PV-027) names a person: not in a copy
        if (l ~ /^Operator: /) continue
        if (l ~ /^Output-SHA256: /) {
            split(l, F, " ")
            if (!(F[2] in OUT256)) continue
            l = "Output-SHA256: " F[2] " " OUT256[F[2]]
        } else {
            l = export_line(l)
            if (PS_DROP) continue
        }
        out = out l "\n"
    }
    if (!ends) out = substr(out, 1, length(out) - 1)
    return out
}
function sline(line,    n, msg, got, l, rest, new, sp, mode_, sha, path, p) {
    if (substr(line, 1, 5) == "data ") {
        n = substr(line, 6) + 0
        msg = ""; got = 0
        while (got < n && (getline l) > 0) { got += length(l) + 1; msg = msg l "\n" }
        rest = ""
        if (got > n) { rest = substr(msg, n + 1); msg = substr(msg, 1, n); sub(/\n$/, "", rest) }
        new = fixmsg(msg)
        printf "data %d\n%s", length(new), new
        if (substr(new, length(new)) != "\n") printf "\n"
        if (rest != "") sline(rest)
        return
    }
    if (substr(line, 1, 2) == "M ") {
        # M <mode> <sha> <path>
        p = substr(line, 3); sp = index(p, " "); mode_ = substr(p, 1, sp - 1)
        p = substr(p, sp + 1); sp = index(p, " "); sha = substr(p, 1, sp - 1); path = substr(p, sp + 1)
        if (!(sha in GM)) { printf "provost: no rewritten blob for %s (%s)\n", sha, path > "/dev/stderr"; exit 3 }
        print "M " mode_ " " GM[sha] " " tpath(path)
        return
    }
    if (substr(line, 1, 2) == "D ") { print "D " tpath(substr(line, 3)); return }
    if (line ~ /^(author|committer|tagger) /) {
        # the name and email; the date after the '>' stays
        p = match(line, />[^>]*$/)
        if (p) { sp = index(line, " "); print substr(line, 1, sp) pseudo(substr(line, sp + 1, RSTART - sp - 1)) substr(line, RSTART); return }
    }
    print line
}

BEGIN {
    if (MODE == "collect" || MODE == "blobs" || MODE == "stream") pseudo_init()
    if (MODE == "blobs" || MODE == "stream") {
        if (OUT256F != "") { while ((getline l < OUT256F) > 0) { split(l, F, "\t"); OUT256[F[1]] = F[2] } close(OUT256F) }
        if (B64F != "") { while ((getline l < B64F) > 0) { n = index(l, "\t"); B64[substr(l, 1, n - 1)] = substr(l, n + 1) } close(B64F) }
    }
    if (MODE == "collect") {
        if (PATHS != "") {              # "sha<TAB>path": which blobs are datasets
            while ((getline l < PATHS) > 0) {
                n = index(l, "\t")
                if (substr(l, n + 1) ~ /^datasets\/.*[.]tsv$/) DSBLOB[substr(l, 1, n - 1)] = 1
                if (substr(l, n + 1) ~ /^datasets\/unsorted([.][^\/]*)?[.]tsv$/) HELDBLOB[substr(l, 1, n - 1)] = 1
            }
            close(PATHS)
        }
        read_batch()
        if (STREAM != "") { while ((getline l < STREAM) > 0) collect(l); close(STREAM) }
        if (HOSTS != "") { while ((getline l < HOSTS) > 0) if (l !~ /^[ \t]*(#|$)/) add_name(l); close(HOSTS) }
        exit
    }
    if (MODE == "blobs") { read_batch(); if (COUNTS != "") redact_counts(COUNTS); exit }
    if (MODE == "stream") {
        if (GITMAP != "") { while ((getline l < GITMAP) > 0) { split(l, F, "\t"); GM[F[1]] = F[2] } close(GITMAP) }
        while ((getline l) > 0) sline(l)
        if (COUNTS != "") redact_counts(COUNTS)
        exit
    }
}
