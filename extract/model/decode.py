# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Whole-table decoding: decide a block's columns once, for all its rows.

The field-start model scores each candidate on its own line, so one table can
come out split differently on different rows. Here every run of consecutive
`row` lines (a block) gets one column decision, made from the summed evidence
of all its rows:

  slot mode   when the block has gutters (columns of spaces running through
              every row), the text between two gutters is a slot. Each slot
              votes once, with the summed log-odds of each row's first
              candidate in it, and becomes a column or not. Right-aligned
              numbers land in the same slot even though their starts differ.
  token mode  when it has no gutters (tables separated by single spaces),
              rows with the same number of whitespace tokens vote per token
              index instead.

Within a slot, a further split survives only when the model is confident
(p > INNER), so `5 minutes ago` stays whole on every row unless the evidence
is strong. Blocks with fewer than MIN_ROWS rows are left as predicted.

Stdlib only: this is also what provost runs at capture time.
"""
import math

MIN_ROWS = 3
INNER = 0.9
CLIP = 6.0


def _logit(p):
    p = min(max(p, 1e-6), 1 - 1e-6)
    return max(-CLIP, min(CLIP, math.log(p / (1 - p))))


def _blocks(roles, probs):
    out, cur = [], []
    for j, r in enumerate(roles):
        if r == "row" and probs[j]:
            cur.append(j)
        else:
            if cur:
                out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return out


def _gutter_runs(lines, rows):
    """[(start, end)] runs of columns that are blank on every row (only
    between text: a run must have text to its left on some row)."""
    width = max(len(lines[j]) for j in rows)
    blank = [all(x >= len(lines[j]) or lines[j][x] == " " for j in rows) for x in range(width)]
    first = min(len(lines[j]) - len(lines[j].lstrip(" ")) for j in rows)
    runs, x = [], first
    while x < width:
        if blank[x]:
            s = x
            while x < width and blank[x]:
                x += 1
            if x < width:
                runs.append((s, x))
        else:
            x += 1
    return runs


def _slot_decode(lines, rows, probs):
    runs = _gutter_runs(lines, rows)
    edges = [e for _, e in runs]          # slot k starts at edges[k-1]

    def slot_of(x):
        k = 0
        for e in edges:
            if x >= e:
                k += 1
        return k

    votes, firsts = {}, {}
    for j in rows:
        seen = set()
        for x, p in sorted(probs[j].items()):
            k = slot_of(x)
            if k not in seen:
                seen.add(k)
                firsts[(j, k)] = x
                votes[k] = votes.get(k, 0.0) + _logit(p)
    out = {}
    for j in rows:
        st = []
        for x, p in sorted(probs[j].items()):
            k = slot_of(x)
            if firsts.get((j, k)) == x:
                if votes[k] > 0:
                    st.append(x)
            elif p > INNER:
                st.append(x)
        out[j] = st or [x for x, p in probs[j].items() if p > 0.5]
    return out


def _token_decode(lines, rows, probs):
    groups = {}
    for j in rows:
        groups.setdefault(len(lines[j].split()), []).append(j)
    out = {}
    for n, js in groups.items():
        if len(js) < MIN_ROWS:
            continue
        tstarts = {j: [i for i, ch in enumerate(lines[j])
                       if not ch.isspace() and (i == 0 or lines[j][i - 1].isspace())] for j in js}
        votes = [0.0] * n
        for j in js:
            for t, x in enumerate(tstarts[j]):
                if x in probs[j]:
                    votes[t] += _logit(probs[j][x])
        for j in js:
            ts = set(tstarts[j])
            st = [x for t, x in enumerate(tstarts[j]) if x in probs[j] and votes[t] > 0]
            st += [x for x, p in probs[j].items() if x not in ts and p > 0.5]
            out[j] = sorted(st) or sorted(x for x, p in probs[j].items() if p > 0.5)
    return out


def decode(lines, roles, probs):
    """lines, roles: per line; probs: per line {position: p} or None.
    Returns {line: [starts]} for the lines it re-decided."""
    out = {}
    for rows in _blocks(roles, probs):
        if len(rows) < MIN_ROWS:
            continue
        if _gutter_runs(lines, rows):
            out.update(_slot_decode(lines, rows, probs))
        else:
            out.update(_token_decode(lines, rows, probs))
    return out
