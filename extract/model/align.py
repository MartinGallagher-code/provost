# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Line a parse's records back up with the input lines it came from.

Given the input and a parse of it as a table (column names + rows of
values), find where each record's values sit in the input: which line holds
a whole record (`row`), a key and its value (`kv`), the column names
(`header`), a continued record (`cont`) or a heading kept as a value
(`section`), and at which offsets each line's fields start.

Two users: ml/corpus_labels.py turns the corpus goldens into training labels
with it, and the layout model at capture time turns the ENGINE's own parse of
a capture into per-line field starts, so the arbiter (arbitrate.py) can
compare the two splits line by line. Stdlib only.
"""
import re

from layout import DELIMS, candidates, is_blank

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


def label_file(text, cols, rows):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    lab = Labeller(lines[:MAX_LINES] if len(lines) > MAX_LINES else lines, cols, rows)
    attempted, matched = lab.label()
    return lab, attempted, matched


def rows_from_wide(wide):
    """The engine's -f tsv output (one header line of flattened names, one
    line of values) as (columns, rows): `entryN.col` names become row N of a
    table; plain names are one record."""
    ls = [ln for ln in wide.split("\n") if ln != ""]
    if len(ls) < 2:
        return [], []
    names, vals = ls[0].split("\t"), ls[1].split("\t")
    vals += [""] * (len(names) - len(vals))
    entries, cols, flat = {}, [], {}
    for n, v in zip(names, vals):
        m = re.match(r"^entry(\d+)\.(.+)$", n)
        if m:
            c = m.group(2)
            if c not in cols:
                cols.append(c)
            entries.setdefault(int(m.group(1)), {})[c] = v
        elif n != "total_entries":
            flat[n] = v
    if entries:
        return cols, [[entries[k].get(c, "") for c in cols] for k in sorted(entries)]
    if flat:
        return list(flat), [list(flat.values())]
    return [], []
