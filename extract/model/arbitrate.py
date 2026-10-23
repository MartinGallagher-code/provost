# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""The arbiter at capture time: on a line where the engine's field split and
the model's differ, keep the one a small logistic regression trusts more.

Its inputs per line: each split's log-likelihood under the model's own
per-candidate probabilities, both field counts, how often neighbouring lines
share each split's count, and the engine's confidence / line coverage /
column consistency for the capture. ml/arbiter.py trains it on hand-labelled
lines (where exactly one of the two is right) and writes arbiter.json; this
module only applies it. Stdlib only.
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
COEFFS = os.path.join(HERE, "arbiter.json")


def loglik(probs, split):
    """probs: [(position, p)] for a line's candidates."""
    s, out = set(split), 0.0
    for x, p in probs:
        p = min(max(p, 1e-4), 1 - 1e-4)
        out += math.log(p if x in s else 1 - p)
    return out


def _consistency(starts, j):
    me = len(starts[j])
    nb = [k for k in range(max(0, j - 3), min(len(starts), j + 4)) if k != j and starts[k]]
    if not nb:
        return -1.0
    return sum(1 for k in nb if len(starts[k]) == me) / len(nb)


def features(eng_starts, mod_starts, probs, j, meta, strategy, role):
    """eng_starts / mod_starts: per line (lists or None); probs: per line
    [(pos, p)]; meta: [confidence, coverage, consistency] (-1 = unknown)."""
    pr = probs[j] or []
    le, lm = loglik(pr, eng_starts[j]), loglik(pr, mod_starts[j])
    return [le - lm, le, lm, len(eng_starts[j]), len(mod_starts[j]),
            len(eng_starts[j]) - len(mod_starts[j]),
            _consistency(eng_starts, j), _consistency(mod_starts, j),
            *meta, float(strategy == "aligned-columns"), float(role == "kv")]


def prefer_engine(model, f):
    z = model["intercept"] + sum(w * x for w, x in zip(model["coef"], f))
    return 1 / (1 + math.exp(-max(-30.0, min(30.0, z)))) > 0.5


def load(path=COEFFS):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def choose(model, roles, eng_starts, mod_starts, probs, meta, strategy):
    """Per line, the split to keep: the engine's where the arbiter prefers it
    and the two differ, else the model's. probs: per line {pos: p} or None.
    Returns (starts per line, number of lines switched to the engine's)."""
    pl = [None if p is None else sorted(p.items()) for p in probs]
    es = [s if s else None for s in eng_starts]
    ms = [s if s else None for s in mod_starts]
    out, switched = list(mod_starts), 0
    for j in range(len(mod_starts)):
        if not ms[j] or not es[j] or sorted(es[j]) == sorted(ms[j]) or pl[j] is None:
            continue
        e_ = [x if x is not None else [] for x in es]
        m_ = [x if x is not None else [] for x in ms]
        if prefer_engine(model, features(e_, m_, pl, j, meta, strategy, roles[j])):
            out[j] = sorted(es[j])
            switched += 1
    return out, switched
