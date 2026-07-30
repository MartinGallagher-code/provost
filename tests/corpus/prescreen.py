#!/usr/bin/env python3
"""Pre-screen corpus review-output for structural tidiness defects.

A review aid, not a gate: it triages the corpus so a human reviewer can skip
the entries that are structurally clean and spend their attention on the rest.
It reads tests/corpus/review-output/*.tsv (plus inputs/ for a coverage check)
and writes a TSV verdict per tool.

Verdicts
  looks-fine       no structural defect found
  looks-fine-thin  no structural defect, but far fewer cells than input lines
                   (possible dropped content -- worth a glance)
  needs-review     at least one structural defect, named in `detail`
  no-output        no review-output row for this input

Calibration against the reviewer marks in docs/ is printed with --validate.
The screen only sees *structure*. A parse that is cleanly rectangular but
split on the wrong boundary reads as fine here, so `looks-fine` means
"nothing mechanically wrong", not "correct".

Usage:
  python3 tests/corpus/prescreen.py [-o docs/review-prescreen-round8.tsv]
  python3 tests/corpus/prescreen.py --validate
  python3 tests/corpus/prescreen.py --emit-json /tmp/good.json   # feeds make_review_doc.js
"""

import argparse
import collections
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "tests", "corpus", "review-output")
IN_DIR = os.path.join(ROOT, "tests", "corpus", "inputs")
DOCS = os.path.join(ROOT, "docs")

# Columns the engine adds; they are not content.
META_COLS = ("n", "total_entries")

# A cell holding "a   b" still has an unsplit column boundary inside it.
UNSPLIT_RE = re.compile(r"\S {2,}\S")
# A row that is just rule characters is a separator the parser should have eaten.
SEP_RE = re.compile(r"[-=+_|\s]{4,}")
# Values that carry no column identity, so they say nothing about alignment.
NUMERIC_RE = re.compile(r"[-+0-9.,%:]+")
# A cell that is itself a `key: value` or `key ....: value` pair -- the
# delimiter (colon, optionally with dot leaders) was left sitting inside the
# cell instead of splitting the row into columns. This is the failure the
# round-8 reviewer caught in gpg-card-status, chronyc-tracking, hammerdb-tpcc:
# a whole key/value line captured as one blob. Guarded to avoid firing on a
# bare `HH:MM` time or a `scheme://` URL, which legitimately carry a colon.
DELIM_IN_CELL_RE = re.compile(r"^\S.*?(?:\.{2,}\s*)?:\s+\S")
TIME_RE = re.compile(r"^\d{1,2}:\d\d")
URL_RE = re.compile(r"://")

# Rates above which a defect is real rather than one odd cell.
UNSPLIT_RATE = 0.10
PIPE_RATE = 0.10
UNTRIMMED_RATE = 0.10
# Fraction of content cells that are themselves an unsplit key: value pair.
DELIM_IN_CELL_RATE = 0.30
# Fraction of repeated tokens landing in more than one column.
MISALIGN_RATE = 0.15
# Captured content cells per non-blank input line.
THIN_RATE = 0.5


def load(name):
    path = os.path.join(OUT_DIR, name + ".tsv")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as fh:
        rows = [r.split("\t") for r in fh.read().rstrip("\n").split("\n") if r != ""]
    return rows or None


def content_idx(header):
    return [i for i, c in enumerate(header) if c not in META_COLS]


def structural_flags(rows):
    """Defects that are wrong regardless of what the tool's output means."""
    header, data = rows[0], rows[1:]
    filled = [c for r in data for c in r if c.strip()]
    flags = []
    if not data:
        flags.append("no-data-rows")
    if any(not c.strip() for c in header):
        flags.append("blank-header-cell")
    if any(len(r) != len(header) for r in data):
        flags.append("ragged-rows")
    if filled:
        n = len(filled)
        if sum(1 for c in filled if UNSPLIT_RE.search(c)) / n > UNSPLIT_RATE:
            flags.append("unsplit-cells")
        if sum(1 for c in filled if "|" in c) / n > PIPE_RATE:
            flags.append("pipes-in-cells")
        if sum(1 for c in filled if c != c.strip()) / n > UNTRIMMED_RATE:
            flags.append("untrimmed-cells")
    if data and any(any(SEP_RE.fullmatch(c or "") for c in r) for r in data):
        flags.append("separator-row-as-data")
    if len(header) > 1 and len(set(header)) != len(header):
        flags.append("duplicate-column-names")
    # Only the content cells can hold a stranded key/value pair -- n and
    # total_entries never do, and counting them would dilute the rate.
    idx = content_idx(header)
    content_cells = [r[i] for r in data for i in idx if i < len(r) and r[i].strip()]
    if content_cells:
        def stranded(c):
            if URL_RE.search(c) or TIME_RE.match(c):
                return False
            return bool(DELIM_IN_CELL_RE.match(c))
        if sum(1 for c in content_cells if stranded(c)) / len(content_cells) > DELIM_IN_CELL_RATE:
            flags.append("key-value-delimiter-in-cell")
        # A cell that is nothing but a lone delimiter means the parser split the
        # delimiter into its own column instead of using it to split key from
        # value -- chronyc-tracking comes out `Reference | ID | : | C0248F01`.
        if any(c.strip() in (":", "=", "|") for c in content_cells):
            flags.append("lone-delimiter-column")
    return flags


def misalignment(rows):
    """Share of repeated tokens that appear under more than one column.

    In an aligned table a given literal keeps its column. When a parser splits
    on the wrong boundary the same token drifts, so this rises.
    """
    header, data = rows[0], rows[1:]
    idx = content_idx(header)
    if len(idx) < 2 or len(data) < 2:
        return 0.0
    where = collections.defaultdict(set)
    for row in data:
        for i in idx:
            if i < len(row):
                v = row[i].strip()
                if v and not NUMERIC_RE.fullmatch(v):
                    where[v].add(i)
    if not where:
        return 0.0
    return sum(1 for cols in where.values() if len(cols) > 1) / len(where)


def thinness(name, rows):
    """Content cells captured per non-blank input line."""
    path = os.path.join(IN_DIR, name + ".txt")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = [l for l in fh.read().split("\n") if l.strip()]
    idx = content_idx(rows[0])
    cells = sum(1 for r in rows[1:] for i in idx if i < len(r) and r[i].strip())
    return cells / max(1, len(lines))


def classify(name):
    rows = load(name)
    if not rows:
        return "no-output", "", 0, ""
    header = rows[0]
    ncontent = len(content_idx(header))
    flags = structural_flags(rows)
    mis = misalignment(rows)
    if mis > MISALIGN_RATE:
        flags.append("column-misalignment=%.2f" % mis)
    joined = " / ".join(header)[:80]
    if flags:
        return "needs-review", ";".join(flags), ncontent, joined
    thin = thinness(name, rows)
    if thin is not None and thin < THIN_RATE:
        return "looks-fine-thin", "cells-per-line=%.2f" % thin, ncontent, joined
    return "looks-fine", "strong" if ncontent >= 3 and len(rows) >= 3 else "good", ncontent, joined


def corpus_names():
    return sorted(os.path.splitext(f)[0] for f in os.listdir(IN_DIR))


# --- risk ranking, for the human verification pass ------------------------
# Everything scored here already *passed* the screen. The score orders those
# passes by how likely the pass is to be wrong, so a reviewer checking the
# screen can start where it is weakest instead of reading 3,000 entries.

HEADERISH_RE = re.compile(r"^[A-Z][A-Z0-9_()/%.-]*$")


def risk(name, verdict, rows):
    header, data = rows[0], rows[1:]
    content = [c for c in header if c not in META_COLS]
    idx = content_idx(header)
    cells = [r[i] for r in data for i in idx if i < len(r) and r[i].strip()]
    generic = [c for c in content if re.fullmatch(r"[A-Z]", c)]
    all_generic = bool(content) and len(generic) == len(content)

    score, why = 0, []
    if verdict == "looks-fine-thin":
        score += 4
        why.append("few captured cells vs input lines")
    if all_generic:
        score += 3
        why.append("all columns unnamed (A/B/C)")
    if len(content) < 2:
        score += 2
        why.append("single content column")
    if cells and sum(1 for c in cells if "..." in c or c.rstrip().endswith(":")) / len(cells) > 0.15:
        score += 2
        why.append("dot-leaders / trailing colons kept in cells")
    if cells and sum(1 for c in cells if "=" in c) / len(cells) > 0.15:
        score += 1
        why.append("'=' left inside cells")
    if all_generic:
        path = os.path.join(IN_DIR, name + ".txt")
        first = ""
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                first = next((l for l in fh.read().split("\n") if l.strip()), "")
        if sum(1 for w in first.split() if HEADERISH_RE.fullmatch(w)) >= 2:
            score += 2
            why.append("source looks like it has a header row, but columns came out unnamed")
    if len(data) == 1 and len(content) >= 6:
        score += 1
        why.append("single wide row")
    return score, "; ".join(why) or "no risk signals"


# Control characters are illegal in Word XML. The corpus carries plenty (ANSI
# colour escapes), and they matter to a reviewer judging the parse, so show
# them as Unicode control pictures rather than dropping them.
def _visible(ch):
    o = ord(ch)
    if o == 0x7F:
        return "␡"
    if o < 0x20:
        return chr(0x2400 + o)
    return ch


def _expand_tabs(s, width=8):
    out = ""
    for ch in s:
        out += " " * (width - len(out) % width) if ch == "\t" else ch
    return out


def sanitize(s, expand=False):
    s = _expand_tabs(s) if expand else s.replace("\t", " ")
    return "".join(_visible(c) for c in s)


def emit_json(path):
    """Risk-ranked JSON of every passing entry, for make_review_doc.js."""
    import json

    done = validated()
    out = []
    for name in corpus_names():
        if name in done:
            continue
        verdict, detail, ncontent, _ = classify(name)
        if not verdict.startswith("looks-fine"):
            continue
        rows = load(name)
        score, why = risk(name, verdict, rows)
        src_path = os.path.join(IN_DIR, name + ".txt")
        src = []
        if os.path.exists(src_path):
            with open(src_path, encoding="utf-8", errors="replace") as fh:
                src = fh.read().rstrip("\n").split("\n")
        out.append({
            "name": name, "verdict": verdict, "tier": detail,
            "risk": score, "why": why, "ncontent": ncontent,
            "input": [sanitize(l, expand=True) for l in src],
            "table": [[sanitize(c) for c in r] for r in rows],
        })
    out.sort(key=lambda d: (-d["risk"], d["name"]))
    for i, d in enumerate(out, 1):
        d["rank"] = i
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    print("wrote %s — %d entries" % (path, len(out)))


def validated():
    path = os.path.join(DOCS, "review-validated-cumulative.txt")
    with open(path, encoding="utf-8") as fh:
        return set(fh.read().split())


def marks():
    """Latest reviewer mark per tool across the round 1-3 marks files."""
    out = {}
    for fn in sorted(os.listdir(DOCS)):
        if not fn.startswith("review-marks-"):
            continue
        with open(os.path.join(DOCS, fn), encoding="utf-8") as fh:
            for row in csv.DictReader(fh, delimiter="\t"):
                m = row["mark"].strip()
                out[row["name"]] = "mixed" if ";" in m else m.split("=")[0].strip()
    return out


def validate():
    """Report how the screen scores entries the reviewer already judged."""
    known = marks()
    groups = [
        ("validated (known good)", sorted(validated())),
        ("Horrible (known bad)", sorted(n for n, v in known.items() if v == "Horrible")),
        ("Not quite (known iffy)", sorted(n for n, v in known.items() if v == "Not quite")),
    ]
    for label, names in groups:
        counts = collections.Counter(classify(n)[0] for n in names if load(n))
        total = sum(counts.values())
        if not total:
            continue
        passed = counts["looks-fine"] + counts["looks-fine-thin"]
        print("%-24s n=%-4d passes=%3d (%2.0f%%)  %s"
              % (label, total, passed, 100.0 * passed / total, dict(counts.most_common())))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", help="write the verdict TSV here")
    ap.add_argument("--skip-validated", action="store_true", default=True,
                    help="omit tools already in review-validated-cumulative.txt (default)")
    ap.add_argument("--all", dest="skip_validated", action="store_false",
                    help="include already-validated tools")
    ap.add_argument("--validate", action="store_true",
                    help="score the screen against the reviewer marks and exit")
    ap.add_argument("--emit-json", metavar="PATH",
                    help="write risk-ranked JSON of the passing entries for make_review_doc.js")
    args = ap.parse_args()

    if args.validate:
        validate()
        return 0

    if args.emit_json:
        emit_json(args.emit_json)
        return 0

    done = validated() if args.skip_validated else set()
    rows, tally = [], collections.Counter()
    for name in corpus_names():
        if name in done:
            continue
        verdict, detail, ncontent, header = classify(name)
        tally[verdict] += 1
        rows.append((name, verdict, detail, str(ncontent), header))

    for verdict, count in tally.most_common():
        print("  %-18s %5d" % (verdict, count))
    print("  %-18s %5d" % ("TOTAL", sum(tally.values())))

    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write("name\tverdict\tdetail\tcontent_cols\theader\n")
            for r in rows:
                fh.write("\t".join(r) + "\n")
        print("wrote %s" % args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
