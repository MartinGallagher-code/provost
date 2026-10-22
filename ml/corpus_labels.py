#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Derive layout-model labels from the tidy corpus.

For each tests/corpus/inputs/<tool>.txt with a frozen golden
tests/corpus/expected/<tool>.tsv, line the golden's cells back up with the raw
lines: a line holding a whole record is a `row`, one holding a key and its
value is `kv`, the line naming the columns is the `header`, and so on (roles
in layout.py). Where every value on a line is found in order at a field-start
candidate, the line's field starts are recorded too.

The goldens are what provost's generic parsers produce today, not hand labels,
so they carry its mistakes. Two filters keep the worst of that out:
  * strategies whose output does not live on the input lines (grammar
    formats, trees, the text-lines catch-all) are skipped outright;
  * a file is kept only when >= MIN_MATCH of its records line up.

Stdlib only. Usage:
    python3 ml/corpus_labels.py [--meta DIR] [-o ml/data/corpus.jsonl]
--meta is a directory of <tool>.meta files from
`provost-extract --batch --batch-out DIR --generic`; without it the engine is
run here (a few minutes).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layout import DELIMS, candidates, is_blank  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(ROOT, "tests", "corpus")

# Output that is not a layout of the input lines: grammar formats (exact
# parsers already handle them), derived structure (tree depth/parent columns),
# and the catch-alls that mean "no structure found".
SKIP_STRATEGIES = {
    "json", "json-array", "jsonl", "xml", "toml", "har", "ndjson",
    "tree-view", "indent-tree", "indented-hierarchy", "group-children",
    "kv-under-group", "text-lines", "vertical-line", "(none)", "",
}
MAX_LINES = 400      # label at most this many lines per input
MIN_MATCH = 0.9      # keep a file when this share of its records line up
ROW_WINDOW = 40      # lines searched ahead for the next record
EMPTY = {"", '""', "''"}
POSITIONAL = re.compile(r"^[A-Z]{1,2}$")
KV_COLS = {("key", "value"), ("name", "value"), ("field", "value"),
           ("property", "value"), ("setting", "value"), ("item", "value")}


def find_span(line, v, start=0):
    """(start, end) of the first whole-field occurrence of v at >= start, or
    (-1, -1). Runs of whitespace inside v match any run (goldens collapse
    alignment padding inside a value)."""
    if not v:
        return -1, -1
    words = v.split()
    if len(words) > 1:
        it = ((m.start(), m.end()) for m in
              re.finditer(r"\s+".join(map(re.escape, words)), line[start:]))
        it = ((a + start, b + start) for a, b in it)
    else:
        def plain():
            i = line.find(v, start)
            while i >= 0:
                yield i, i + len(v)
                i = line.find(v, i + 1)
        it = plain()
    for i, e in it:
        left = i == 0 or line[i - 1] in DELIMS
        right = e == len(line) or line[e] in DELIMS or not v[-1].isalnum()
        if left and right:
            return i, e
    return -1, -1


def find_tok(line, v, start=0):
    return find_span(line, v, start)[0]


def find_name(line, name, start=0):
    """A column name, as the golden normalised it (spaces became _)."""
    base = re.sub(r"_\d+$", "", name)
    for cand in (name, base, base.replace("_", " ")):
        i = find_tok(line, cand, start)
        if i >= 0:
            return i, len(cand)
        low = find_tok(line.lower(), cand.lower(), start)
        if low >= 0:
            return low, len(cand)
    return -1, 0


def match_seq(line, vals):
    """Find vals in order; return (positions with -1 for misses, n found)."""
    pos, cur, n = [], 0, 0
    for v in vals:
        i, e = find_span(line, v, cur)
        pos.append(i)
        if i >= 0:
            cur, n = e, n + 1
    return pos, n


def read_golden(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        rows = [ln.rstrip("\n").split("\t") for ln in fh if ln.strip()]
    if not rows:
        return [], []
    cols, body = rows[0], rows[1:]
    if cols and cols[0] == "n":
        cols, body = cols[1:], [r[1:] for r in body]
    body = [(r + [""] * len(cols))[: len(cols)] for r in body]
    return cols, body


class Labeller:
    def __init__(self, lines, cols, rows):
        self.lines = lines
        self.n = len(lines)
        self.cols, self.rows = cols, rows
        self.roles = ["blank" if is_blank(ln) else None for ln in lines]
        self.starts = [None] * self.n
        self.named = [c for c in cols if not POSITIONAL.match(c)]
        low = tuple(c.lower() for c in cols)
        self.kv_shape = low in KV_COLS
        self.wide_one = len(rows) == 1 and len(self.named) >= 2 and not self.kv_shape

    def free(self, j):
        return self.roles[j] is None

    # -- one record on one line, maybe with a section line above ------------
    def try_single(self, j, vals, names):
        pos, n = match_seq(self.lines[j], vals)
        if n == len(vals):
            return pos, None
        if n * 2 < len(vals) or not any(
                p >= 0 and (len(v) > 1 and not v.isdigit()) for p, v in zip(pos, vals)):
            return None
        missing = [(v, c) for p, v, c in zip(pos, vals, names) if p < 0]
        for k in range(j - 1, max(-1, j - 200), -1):
            if not (self.free(k) or self.roles[k] == "section"):
                continue
            line = self.lines[k]
            if all(find_tok(line, v) >= 0 for v, _ in missing):
                # `Package: curl` above `Version: 7.8` is a block record's
                # first field, not a heading: the line itself names its
                # value's column (`Target: x` above a table row is a heading).
                row = self.lines[j]
                if any(p >= 0 and find_name(row[:p], c)[0] >= 0
                       for p, c in zip(pos, names)):
                    return None
                return pos, k
        return None

    # -- one record spread over several lines -------------------------------
    def try_multi(self, j, vals, span):
        touched, cur_line, cur, k = {}, j, 0, 0
        while k < len(vals):
            if cur_line >= self.n or cur_line - j > span:
                return None
            if self.roles[cur_line] == "blank":
                cur_line, cur = cur_line + 1, 0
                continue
            if not self.free(cur_line):
                return None
            i, e = find_span(self.lines[cur_line], vals[k], cur)
            if i >= 0:
                touched.setdefault(cur_line, []).append((k, i))
                cur = e
                k += 1
            elif k == 0:
                return None
            else:
                cur_line, cur = cur_line + 1, 0
        return touched

    def label(self):
        p, attempted, matched = 0, 0, 0
        for r in self.rows:
            if p >= min(self.n, MAX_LINES):
                break
            idx = [c for c, v in enumerate(r) if v.strip() not in EMPTY]
            vals = [r[c].strip() for c in idx]
            names = [self.cols[c] for c in idx]
            if not vals:
                continue
            attempted += 1
            hit = None
            if not self.wide_one:
                for j in range(p, min(self.n, p + ROW_WINDOW)):
                    if not self.free(j):
                        continue
                    got = self.try_single(j, vals, names)
                    if got:
                        hit = ("single", j, got)
                        break
            if hit is None:
                span = 80 if self.wide_one else 12
                for j in range(p, min(self.n, p + ROW_WINDOW)):
                    if self.free(j) and find_tok(self.lines[j], vals[0]) >= 0:
                        got = self.try_multi(j, vals, span)
                        if got:
                            hit = ("multi", j, got)
                        break
            if hit is None:
                continue
            matched += 1
            if hit[0] == "single":
                _, j, (pos, sec) = hit
                if sec is not None:
                    self.roles[sec] = "section"
                self.roles[j] = "kv" if self.kv_shape else "row"
                found = [q for q in pos if q >= 0]
                if sec is not None or len(found) == len(vals):
                    self.starts[j] = found
                p = j + 1
            else:
                _, j, touched = hit
                first = min(touched)
                for ln, items in sorted(touched.items()):
                    self.roles[ln] = self.multi_role(ln, items, names, ln == first)
                p = max(touched) + 1
        self.mark_headers()
        self.mark_empty_kv()
        for j in range(self.n):
            if self.roles[j] is None:
                self.roles[j] = "skip"
            if self.starts[j] and not set(self.starts[j]) <= set(candidates(self.lines[j])):
                self.starts[j] = None
        return attempted, matched

    def multi_role(self, ln, items, names, first):
        line = self.lines[ln]
        if len(items) == 1:
            k, i = items[0]
            if POSITIONAL.match(names[k]) or re.match(r"^line\d+$", names[k]):
                return "section" if line.strip() == line[i:].strip() else ("row" if first else "cont")
            ni, nl = find_name(line[:i], names[k])
            if ni >= 0:
                self.starts[ln] = [ni, i]
                return "kv"
        return "row" if first else "cont"

    def mark_empty_kv(self):
        """`KEY=` / `Key:` lines whose value is empty: the golden cell is
        blank, so the record matcher never saw them."""
        if not any(r == "kv" for r in self.roles):
            return
        for j in range(self.n):
            if not self.free(j):
                continue
            m = re.match(r"^(\s*)(.+?)\s*[:=]\s*$", self.lines[j])
            if m and any(find_name(m.group(2), c)[0] == 0 for c in self.cols):
                self.roles[j] = "kv"
                self.starts[j] = [len(m.group(1))]

    def mark_headers(self):
        if len(self.named) < 1 or self.wide_one or self.kv_shape:
            return
        need = max(2, (len(self.named) + 1) // 2) if len(self.named) > 1 else 1
        for j in range(min(self.n, MAX_LINES)):
            if not self.free(j):
                continue
            line, cur, got = self.lines[j], 0, []
            for c in self.named:
                i, ln = find_name(line, c, cur)
                if i >= 0:
                    got.append(i)
                    cur = i + ln
            if len(got) >= need:
                self.roles[j] = "header"
                if len(got) == len(self.named) == len(self.cols):
                    self.starts[j] = got


def strategies_from_engine(names):
    out = tempfile.mkdtemp(prefix="provost-ml-meta.")
    engine = os.path.join(ROOT, "extract", "provost-extract")
    paths = [os.path.join(CORPUS, "inputs", n + ".txt") for n in names]
    jobs = max(1, os.cpu_count() or 1)
    env = dict(os.environ)
    env.pop("GIT_DIR", None)
    procs = []
    for k in range(jobs):
        chunk = "\n".join(paths[k::jobs]) + "\n"
        pr = subprocess.Popen(["bash", engine, "--batch", "--batch-out", out, "--generic",
                               "-f", "tsv", "--max-strategies", "1"],
                              stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, env=env, text=True)
        pr.stdin.write(chunk)
        pr.stdin.close()
        procs.append(pr)
    for pr in procs:
        pr.wait()
    return out


def strategy_of(meta_dir, name):
    try:
        with open(os.path.join(meta_dir, name + ".meta"), encoding="utf-8") as fh:
            for ln in fh:
                f = ln.rstrip("\n").split("\t")
                if f[0] == "__EXTRACT_META__" and len(f) > 1:
                    return f[1]
    except OSError:
        pass
    return "(none)"


def label_file(text, cols, rows):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    lab = Labeller(lines[:MAX_LINES] if len(lines) > MAX_LINES else lines, cols, rows)
    attempted, matched = lab.label()
    return lab, attempted, matched


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--meta", help="dir of <tool>.meta from a --generic --batch run")
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "ml", "data", "corpus.jsonl"))
    a = ap.parse_args(argv)
    names = sorted(f[:-4] for f in os.listdir(os.path.join(CORPUS, "expected")) if f.endswith(".tsv"))
    meta = a.meta or strategies_from_engine(names)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    kept = dropped_strat = dropped_match = 0
    roles_seen = {}
    with open(a.out, "w", encoding="utf-8") as out:
        for name in names:
            strat = strategy_of(meta, name)
            if strat in SKIP_STRATEGIES:
                dropped_strat += 1
                continue
            with open(os.path.join(CORPUS, "inputs", name + ".txt"), encoding="utf-8",
                      errors="replace") as fh:
                text = fh.read()
            cols, rows = read_golden(os.path.join(CORPUS, "expected", name + ".tsv"))
            if not rows:
                dropped_match += 1
                continue
            lab, att, mat = label_file(text, cols, rows)
            if att == 0 or mat < MIN_MATCH * att:
                dropped_match += 1
                continue
            kept += 1
            for r in lab.roles:
                roles_seen[r] = roles_seen.get(r, 0) + 1
            out.write(json.dumps({"name": name, "source": "corpus", "strategy": strat,
                                  "lines": lab.lines, "roles": lab.roles,
                                  "starts": lab.starts}, ensure_ascii=False) + "\n")
    print(f"kept {kept} files; dropped {dropped_strat} (strategy not a line layout), "
          f"{dropped_match} (records did not line up)", file=sys.stderr)
    print("roles: " + ", ".join(f"{k}={v}" for k, v in sorted(roles_seen.items())), file=sys.stderr)


if __name__ == "__main__":
    main()
