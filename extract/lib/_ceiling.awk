# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# _ceiling.awk -- the confidence ceilings of strategy files, in one pass over
# all of them (QD-056): one line per file, CEILING<TAB>PATH.
#
# A strategy's ceiling is the highest _STRATEGY_CONFIDENCE its detect can
# ever set: its `## Confidence-Max: N` header when it has one (the last such
# line), else 100 when it assigns a computed value (_STRATEGY_CONFIDENCE=$x),
# else the largest literal it assigns, and never below 50 (the default
# _detect_strategy starts from). Comment lines are not read for assignments.
#
# A file with no lines is never seen by awk, so it gets no line here; the
# caller (_strategy_ceiling in _discovery.sh, and provost's batch) gives an
# empty file 50 and an unreadable one 100, as the per-file scan this replaces
# did. POSIX awk only: it runs under mawk, gawk and BSD awk.
BEGIN { OFS = "\t" }
function flush() {
    if (cur == "") return
    if (have) print hdr, cur
    else if (computed) print 100, cur
    else print (mx > 50 ? mx : 50), cur
}
FNR == 1 { flush(); cur = FILENAME; hdr = 0; have = 0; computed = 0; mx = 0 }
/^## Confidence-Max:/ { hdr = $3 + 0; have = 1 }
{
    line = $0; sub(/^[ \t]+/, "", line)
    if (line ~ /^#/) next
    while ((i = index(line, "_STRATEGY_CONFIDENCE=")) > 0) {
        rest = substr(line, i + 21)
        if (match(rest, /^[0-9]+/)) {
            v = substr(rest, 1, RLENGTH) + 0; if (v > mx) mx = v
        } else computed = 1
        line = rest
    }
}
END { flush() }
