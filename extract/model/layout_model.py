#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""provost's learned layout model, at capture time (stdlib only).

Reads command output, labels every line's role (header, row, cont, kv,
section, skip) and where its fields start, decides each table's columns once
for all its rows (decode.py), and prints the engine's flat record format:

    entry1.Filesystem /dev/sda1        (a table: one entry per row)
    MemTotal 8173456 kB                (key/value lines: one record)
    total_entries 3

Every value is cut from the input; the model only decides where. The
`layout-model` strategy (extract/strategies/structured/layout-model.sh) runs
this when provost asks for it explicitly, which it does only for a capture
the quality gate would otherwise hold (PROVOST_MODEL=1); the engine then
measures the result with the same coverage and consistency checks as every
other parser.

Exit status: 0 with records on stdout; 1 when nothing usable was found;
3 when the input is too large to label here (MAX_LINES).

    python3 layout_model.py [FILE|-] [--debug]
"""
import gzip
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from decode import decode  # noqa: E402
from features import cand_features, line_rows  # noqa: E402
from layout import fields, is_blank  # noqa: E402

MODEL = os.path.join(HERE, "layout-model.json.gz")
MAX_LINES = 600


def load(path=MODEL):
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        return json.load(fh)


def _walk(node, x):
    while type(node) is list:
        node = node[2] if x[node[0]] <= node[1] else node[3]
    return node


def predict_roles(model, X):
    k = model["roles"]["num_class"]
    trees = model["roles"]["trees"]
    out = []
    for x in X:
        s = [0.0] * k
        for i, t in enumerate(trees):
            s[i % k] += _walk(t, x)
        out.append(model["classes"][max(range(k), key=s.__getitem__)])
    return out


def predict_starts(model, X):
    trees = model["starts"]["trees"]
    out = []
    for x in X:
        z = sum(_walk(t, x) for t in trees)
        out.append(1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, z)))))
    return out


def label(model, lines):
    """roles per line, and per scored line {position: p} plus the decided starts."""
    ex = {"lines": lines, "roles": ["skip"] * len(lines), "starts": [None] * len(lines)}
    rows = line_rows(ex)
    roles = ["blank" if is_blank(ln) else "skip" for ln in lines]
    if rows:
        for (_, _, j), r in zip(rows, predict_roles(model, [f for f, _, _ in rows])):
            roles[j] = r
    probs = [None] * len(lines)
    for j, ln in enumerate(lines):
        if roles[j] not in ("row", "header", "kv", "cont"):
            continue
        cf = cand_features(lines, j)
        if cf:
            probs[j] = dict(zip([i for i, _ in cf], predict_starts(model, [f for _, f in cf])))
    starts = [None if p is None else sorted(i for i, q in p.items() if q > 0.5) for p in probs]
    for j, st in decode(lines, roles, probs).items():
        starts[j] = st
    return roles, starts


# -- turning labels into records ---------------------------------------------
_KEYCHARS = re.compile(r"[^\w.%()/+#@-]+")


def _name(s):
    s = s.strip().rstrip(":=").strip()
    return _KEYCHARS.sub("_", s).strip("_") or "field"


def _uniq(names):
    seen, out = {}, []
    for n in names:
        seen[n] = seen.get(n, 0) + 1
        out.append(n if seen[n] == 1 else f"{n}_{seen[n]}")
    return out


def _letters(i):
    s = ""
    i += 1
    while i:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def _section_text(line):
    return line.strip().strip("=-#*[]:~ ").strip() or line.strip()


def _cells(line, st):
    return [(s0, v) for s0, v in zip(st, fields(line, st)) if v != ""]


UNMATCHED = 4.0   # cost of leaving a row cell without a header column


def _align(row, header):
    """Map a row's cells onto header columns, in order. A cell matches the
    column whose start (left-aligned) or end (right-aligned) is nearest;
    a cell may stay unmatched (a column the header doesn't name: `Mem:` in
    `free`) and a column may stay empty. Returns a column index or None per
    cell (cheapest strictly increasing assignment)."""
    n, m = len(row), len(header)
    if n == m:
        return list(range(m))
    INF = float("inf")

    def dist(c, h):
        (cs, cv), (hs, hv) = c, h
        return min(abs(cs - hs), abs((cs + len(cv)) - (hs + len(hv))))

    cost = [[INF] * (m + 1) for _ in range(n + 1)]
    back = [[None] * (m + 1) for _ in range(n + 1)]
    cost[0][0] = 0.0
    for i in range(n + 1):
        for k in range(m + 1):
            if i == 0 and k == 0:
                continue
            best, how = INF, None
            if k > 0 and cost[i][k - 1] < best:                       # column k-1 empty
                best, how = cost[i][k - 1], "skip_col"
            if i > 0 and cost[i - 1][k] + UNMATCHED < best:           # cell i-1 unnamed
                best, how = cost[i - 1][k] + UNMATCHED, "skip_cell"
            if i > 0 and k > 0 and cost[i - 1][k - 1] + dist(row[i - 1], header[k - 1]) < best:
                best, how = cost[i - 1][k - 1] + dist(row[i - 1], header[k - 1]), "match"
            cost[i][k], back[i][k] = best, how
    out, i, k = [None] * n, n, m
    while i > 0 or k > 0:
        how = back[i][k]
        if how == "match":
            out[i - 1] = k - 1
            i, k = i - 1, k - 1
        elif how == "skip_cell":
            i -= 1
        else:
            k -= 1
    return out


def _resplit_header(line, st, rows):
    """A header names the columns the rows show: also start a header cell at
    every header word that begins where row cells begin, or ends where they
    end (right-aligned numbers), on at least half the rows."""
    if not rows:
        return st
    sc, ec = {}, {}
    for cells in rows:
        for s0, v in cells:
            sc[s0] = sc.get(s0, 0) + 1
            ec[s0 + len(v)] = ec.get(s0 + len(v), 0) + 1
    half = len(rows) / 2
    out = set(st)
    words = [(mt.start(), mt.end()) for mt in re.finditer(r"\S+", line)]
    for ws, we in words:
        if sc.get(ws, 0) >= half or ec.get(we, 0) >= half:
            out.add(ws)
    # Two or more row columns inside one header cell (`Stratum Poll Reach`
    # read as one name): split the cell at the word nearest each column.
    cols = sorted(c for c, k in sc.items() if k >= half)
    edges = sorted(out) + [len(line) + 1]
    for a, b in zip(edges, edges[1:]):
        inside = [c for c in cols if a - 2 <= c < b]
        cand = [(ws, we) for ws, we in words if a <= ws < b]
        if len(inside) < 2 or len(cand) < len(inside):
            continue
        nxt = 0   # each column takes its own word, in order
        for n_left, c in zip(range(len(inside), 0, -1), inside):
            pool = cand[nxt:len(cand) - n_left + 1]
            k = min(range(len(pool)), key=lambda q: min(abs(c - pool[q][0]), abs(c - (pool[q][1] - 1))))
            out.add(pool[k][0])
            nxt += k + 1
    return sorted(out)


def _kv(line, st):
    """(key, value) of a key/value line, cut at its first two field starts."""
    if len(st) > 1:
        return _name(line[st[0]:st[1]]), line[st[1]:].strip()
    m = re.match(r"^\s*(.+?)\s*[:=]\s*(.*)$", line)
    return (_name(m.group(1)), m.group(2).strip()) if m else None


MIN_TABLE_ROWS = 3
MAIN_SHARE = 0.6     # the main table holds this share of all rows
SAME_FIELDS = 0.7    # and this share of its rows have one field count
KV_SHARE = 0.6       # key/value lines are this share of the content lines


def shape(lines, roles, starts):
    """What the document is, or None when it is neither one table nor one
    key/value record — a mixed report is AUTO-MULTI's job, not the model's,
    and declining leaves the capture held exactly as before. Returns
    (mode, kept line indexes) with mode 'table' or 'kv'."""
    content = [j for j, r in enumerate(roles) if r not in ("blank", "skip")]
    if not content:
        return None, set()
    blocks, cur = [], []
    for j, r in enumerate(roles):
        if r in ("row", "cont") and (r == "cont" or starts[j]):
            cur.append(j)
        else:
            if cur:
                blocks.append(cur)
            cur = []
    if cur:
        blocks.append(cur)

    def nrows(b):
        return sum(1 for j in b if roles[j] == "row")

    def mode_fields(b):
        counts = {}
        for j in b:
            if roles[j] == "row":
                k = len(starts[j])
                counts[k] = counts.get(k, 0) + 1
        k, c = max(counts.items(), key=lambda kv: kv[1]) if counts else (0, 0)
        return k, c

    all_rows = sum(nrows(b) for b in blocks)
    if blocks:
        main = max(blocks, key=nrows)
        k, c = mode_fields(main)
        if nrows(main) >= MIN_TABLE_ROWS and nrows(main) >= MAIN_SHARE * all_rows \
                and c >= SAME_FIELDS * nrows(main):
            keep = set(main)
            for b in blocks:   # sectioned tables: other blocks of the same shape
                if b is not main and nrows(b) >= 1 and mode_fields(b)[0] == k:
                    keep |= set(b)
            return "table", keep
    kv = [j for j in content if roles[j] == "kv"]
    if len(kv) >= MIN_TABLE_ROWS and len(kv) >= KV_SHARE * len(content):
        return "kv", set(kv)
    return None, set()


def records(lines, roles, starts):
    """Flat records (list of 'key value' strings) from the labels."""
    mode, keep = shape(lines, roles, starts)
    if mode is None:
        return []
    out = []
    if mode == "kv":
        recs, cur, section = [], {}, ""
        for j, ln in enumerate(lines):
            if roles[j] == "section":
                section = _section_text(ln)
            if roles[j] != "kv" or not starts[j]:
                continue
            kv = _kv(ln, starts[j])
            if kv is None:
                continue
            key, val = kv
            if section:
                key = f"{_name(section)}.{key}"
            if key in cur:
                recs.append(cur)
                cur = {}
            cur[key] = val
        if cur:
            recs.append(cur)
        if len(recs) == 1:
            out = [f"{k} {v}" for k, v in recs[0].items()]
        else:
            for n, r in enumerate(recs, 1):
                out += [f"entry{n}.{k} {v}" for k, v in r.items()]
            out.append(f"total_entries {len(recs)}")
        return out

    entry, header, names, section, last = 0, None, None, "", None
    any_section = any(r == "section" for r in roles)
    for j, ln in enumerate(lines):
        r = roles[j]
        if r == "section":
            section, header, names = _section_text(ln), None, None
        elif r == "header" and starts[j]:
            below = []
            for k in range(j + 1, len(lines)):
                if roles[k] == "row" and starts[k]:
                    below.append(_cells(lines[k], starts[k]))
                elif roles[k] not in ("cont", "skip", "blank"):
                    break
            header = _cells(ln, _resplit_header(ln, starts[j], below))
            names = _uniq([_name(v) for _, v in header])
        elif r == "cont" and last is not None and j in keep:
            out[last] += " " + ln.strip()
        elif r == "row" and starts[j] and j in keep:
            cells = _cells(ln, starts[j])
            if not cells:
                continue
            entry += 1
            if header:
                cols = _align(cells, header)
                vals = {}
                for i, ((_, v), c) in enumerate(zip(cells, cols)):
                    key = names[c] if c is not None else _letters(i)
                    vals[key] = f"{vals[key]} {v}" if key in vals else v
            else:
                vals = {_letters(i): v for i, (_, v) in enumerate(cells)}
            if any_section and section:
                out.append(f"entry{entry}.section {section}")
            for k, v in vals.items():
                out.append(f"entry{entry}.{k} {v}")
            last = len(out) - 1
    if entry:
        out.append(f"total_entries {entry}")
    return out


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    debug = "--debug" in argv
    args = [a for a in argv if a != "--debug"]
    src = args[0] if args else "-"
    data = sys.stdin.read() if src == "-" else open(src, encoding="utf-8", errors="replace").read()
    lines = data.replace("\r\n", "\n").split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    if len(lines) > MAX_LINES:
        return 3
    model = load()
    roles, starts = label(model, lines)
    if debug:
        for ln, r, st in zip(lines, roles, starts):
            sys.stderr.write(f"{r:8}|{ln}\n" + (f"{'':8}|{' ' * min(st)}{'^'} {st}\n" if st else ""))
    out = records(lines, roles, starts)
    if not out:
        return 1
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
