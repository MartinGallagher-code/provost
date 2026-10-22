# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Hand-made features for the tree baseline (train_baseline.py).

Two tasks, both read off the same labelled examples (layout.py):
  * line_rows()  one row per non-blank line -> its role
  * cand_rows()  one row per field-start candidate on a line whose fields
                 are known -> does a field start here?

Stdlib only; the trainer turns the lists into arrays.
"""
import re

from layout import PREDICTED, candidates, is_blank

RULE = re.compile(r"[\s\-=_+*~#.|:┌┬┐├┼┤└┴┘─━│┃═║╔╗╚╝╠╣╦╩╬]+")
COLON_KV = re.compile(r"^\s*[^\s:][^:]{0,48}?:(\s|$)")
EQ_KV = re.compile(r"^\s*[\w.\-/]+\s*=")
GAP_KV = re.compile(r"^\s*\S.{0,40}?\S\s{2,}\S")
NUM = re.compile(r"^[-+]?[\d.,:/%]+[A-Za-z%]{0,3}$")
TITLE = re.compile(r"^\s*(==+|--+|#+|\[)\s*\S.*?(==+|--+|\])?\s*$")


def tokens(line):
    return line.split()


def token_starts(line):
    return [i for i, ch in enumerate(line) if not ch.isspace() and (i == 0 or line[i - 1].isspace())]


def base(line):
    s = line.rstrip()
    n = max(1, len(s))
    toks = tokens(s)
    nt = max(1, len(toks))
    letters = [c for c in s if c.isalpha()]
    gaps2 = len(re.findall(r"\S\s{2,}(?=\S)", s))
    return [
        len(s), len(s) - len(s.lstrip()), len(toks),
        sum(c.isdigit() for c in s) / n, len(letters) / n,
        (sum(c.isupper() for c in letters) / len(letters)) if letters else 0.0,
        sum(not c.isalnum() and not c.isspace() for c in s) / n,
        s.count("|") + s.count("│") + s.count("┃"), s.count(","), s.count(";"),
        s.count(":"), s.count("="), s.count("\t"),
        1.0 if RULE.fullmatch(s.strip() or "x") and len(s.strip()) >= 3 else 0.0,
        1.0 if s.endswith(":") else 0.0,
        1.0 if COLON_KV.match(s) else 0.0,
        1.0 if EQ_KV.match(s) else 0.0,
        1.0 if GAP_KV.match(s) else 0.0,
        1.0 if TITLE.match(s) else 0.0,
        1.0 if s.lstrip()[:1] in "[(<" else 0.0,
        1.0 if s.lstrip()[:1] in "#$>" else 0.0,
        sum(bool(NUM.match(t)) for t in toks) / nt,
        1.0 if toks and toks[0].endswith(":") else 0.0,
        gaps2,
        max((len(m) for m in re.findall(r"(?<=\S)\s+(?=\S)", s)), default=0),
        len(candidates(s)),
        1.0 if letters and s.upper() == s and len(toks) <= 6 else 0.0,
    ]


NBASE = len(base("x"))


def _neighbours(lines, j, step, k=1):
    out, i = [], j + step
    while 0 <= i < len(lines) and len(out) < k:
        if not is_blank(lines[i]):
            out.append(i)
        i += step
    return out


def _align(a, b):
    sa, sb = set(token_starts(a)), set(token_starts(b))
    return len(sa & sb) / max(1, len(sa))


def _gutter(line, others):
    starts = token_starts(line)[1:]
    if not starts or not others:
        return 0.0
    hit = 0
    for s in starts:
        if all(s - 1 >= len(o) or o[s - 1].isspace() for o in others):
            hit += 1
    return hit / len(starts)


def line_rows(ex):
    """[(features, role_index, line_index)] for one example's non-blank lines."""
    lines = ex["lines"]
    feats = [base(ln) if not is_blank(ln) else [0.0] * NBASE for ln in lines]
    ntoks = [len(tokens(ln)) for ln in lines if not is_blank(ln)]
    mode = max(set(ntoks), key=ntoks.count) if ntoks else 0
    nonblank = [j for j, ln in enumerate(lines) if not is_blank(ln)]
    first, last = (nonblank[0], nonblank[-1]) if nonblank else (-1, -1)
    out = []
    for j, ln in enumerate(lines):
        if is_blank(ln):
            continue
        p = _neighbours(lines, j, -1)
        q = _neighbours(lines, j, +1)
        pf = feats[p[0]] if p else [-1.0] * NBASE
        qf = feats[q[0]] if q else [-1.0] * NBASE
        ctx = [lines[i] for i in _neighbours(lines, j, -1, 3) + _neighbours(lines, j, +1, 3)]
        f = feats[j] + pf + qf + [
            j / max(1, len(lines) - 1), float(j == first), float(j == last),
            float(j > 0 and is_blank(lines[j - 1])),
            float(j + 1 < len(lines) and is_blank(lines[j + 1])),
            _align(ln, lines[p[0]]) if p else -1.0,
            _align(ln, lines[q[0]]) if q else -1.0,
            _gutter(ln, ctx),
            float(len(tokens(ln)) == mode), mode,
            float(bool(p) and len(tokens(lines[p[0]])) == len(tokens(ln))),
            float(bool(q) and len(tokens(lines[q[0]])) == len(tokens(ln))),
            float(bool(q) and feats[q[0]][13] == 1.0),   # next line is a rule
            float(bool(p) and feats[p[0]][13] == 1.0),   # previous line is a rule
            float(bool(q) and feats[q[0]][1] > feats[j][1]),  # next line indented deeper
        ]
        role = ex["roles"][j]
        out.append((f, PREDICTED.index(role) if role in PREDICTED else -1, j))
    return out


def _cls(ch):
    if ch == "":
        return 0
    if ch == " ":
        return 1
    if ch == "\t":
        return 2
    return {",": 3, ";": 4, "|": 5, "│": 5, "┃": 5, "║": 5, ":": 6, "=": 7,
            "[": 8, "]": 8, "(": 8, ")": 8, "{": 8, "}": 8, "<": 8, ">": 8,
            '"': 9, "'": 9}.get(ch, 10 if not ch.isalnum() else 11 if ch.isdigit() else 12)


def cand_features(lines, j, window=6):
    """[(position, features)] for every candidate on line j."""
    line = lines[j]
    cands = candidates(line)
    ctx = [lines[i] for i in _neighbours(lines, j, -1, window) + _neighbours(lines, j, +1, window)]
    prev_line = lines[_neighbours(lines, j, -1)[0]] if _neighbours(lines, j, -1) else ""
    next_line = lines[_neighbours(lines, j, +1)[0]] if _neighbours(lines, j, +1) else ""
    pc, nc = set(candidates(prev_line)), set(candidates(next_line))
    ctx_c = [set(candidates(o)) for o in ctx]
    colon = line.find(":")
    after_colon = -1
    if colon >= 0:
        k = colon + 1
        while k < len(line) and line[k].isspace():
            k += 1
        after_colon = k
    gaps2 = len(re.findall(r"\S\s{2,}(?=\S)", line))
    kvish = 1.0 if (COLON_KV.match(line) or EQ_KV.match(line)) else 0.0
    out = []
    for k, i in enumerate(cands):
        g = 0
        while i - g - 1 >= 0 and line[i - g - 1] == " ":
            g += 1
        before = line[i - g - 1] if i - g - 1 >= 0 else ""
        tok_end = i
        while tok_end < len(line) and not line[tok_end].isspace():
            tok_end += 1
        cur = line[i:tok_end]
        ps = line[:i].rstrip().split()
        prev_tok = ps[-1] if ps else ""
        n = len(ctx) or 1
        sp = sum(1 for o in ctx if i - 1 < len(o) and i >= 1 and o[i - 1].isspace()) / n
        sp2 = sum(1 for o in ctx if i - 2 >= 0 and i - 1 < len(o) and o[i - 1] == " " and o[i - 2] == " ") / n
        short = sum(1 for o in ctx if len(o.rstrip()) <= i) / n
        nonsp = sum(1 for o in ctx if i < len(o) and not o[i].isspace()) / n
        cand = sum(1 for c in ctx_c if i in c) / n
        out.append((i, [
            k, len(cands), i / max(1, len(line)), float(k == 0), g, float(before == "\t"),
            _cls(line[i - 1] if i else ""), _cls(before), _cls(line[i]),
            float(bool(NUM.match(cur))), float(bool(NUM.match(prev_tok))),
            float(prev_tok.endswith(":")), float(prev_tok.endswith("=")),
            len(cur), len(prev_tok), float(i == after_colon), gaps2, kvish,
            sp, sp2, short, nonsp, cand, float(i in pc), float(i in nc), len(ctx),
        ]))
    return out


def cand_rows(ex):
    """[(features, label, line_index, position)] for lines with known starts."""
    out = []
    for j, (line, st) in enumerate(zip(ex["lines"], ex["starts"])):
        if not st:
            continue
        gold = set(st)
        for i, f in cand_features(ex["lines"], j):
            out.append((f, 1 if i in gold else 0, j, i))
    return out
