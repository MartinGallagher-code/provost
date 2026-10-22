#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""The arbiter: on a line where the engine's split and the model's differ,
which one to trust.

The two are right on different lines (one or the other on ~91% of fresh
random lines, either alone ~85%), so a small logistic regression picks
per line. Inputs:

  * how likely each split is under the model's own per-candidate
    probabilities (log-likelihood of the engine's split, of the model's,
    and their difference);
  * each split's field count, and how often neighbouring lines have the
    same count under it (a split that keeps the table consistent);
  * the engine's own confidence, line coverage and column consistency for
    the capture (--emit-meta), whether it was aligned-columns, and
    whether the line is key/value.

It is trained on the hand-labelled lines where exactly one of the two is
right. Needs numpy + scikit-learn to train; the result is a handful of
coefficients, applied in plain Python.

    python3 ml/arbiter.py --crossval ml/data/crossval.jsonl --meta DIR
"""
import argparse
import json
import math
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extract", "model"))
import adjudicated as A  # noqa: E402
import dataset as D  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def loglik(probs, split):
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
    return 1 / (1 + math.exp(-z)) > 0.5


def read_meta(meta_dir, name):
    try:
        with open(os.path.join(meta_dir, name + ".meta"), encoding="utf-8") as fh:
            f = fh.readline().rstrip("\n").split("\t")
        return [float(x) if x not in ("-", "") else -1.0 for x in f[2:5]]
    except (OSError, ValueError):
        return [-1.0, -1.0, -1.0]


def _right(g, split):
    t = g["text"]
    p = A.canon(t, split)
    return p == A.canon(t, g["starts"]) or (g["alt"] is not None and p == A.canon(t, g["alt"]))


def main(argv=None):
    import numpy as np
    from sklearn.linear_model import LogisticRegression
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus.jsonl"))
    ap.add_argument("--crossval", default=os.path.join(HERE, "data", "crossval.jsonl"),
                    help="out-of-fold predictions with probs (crossval.py --out)")
    ap.add_argument("--meta", required=True, help="dir of <tool>.meta (engine --emit-meta)")
    ap.add_argument("--save", help="write the trained coefficients (JSON) here")
    a = ap.parse_args(argv)
    corp = {e["name"]: e for e in D.load(a.corpus)}
    cv = {e["name"]: e for e in D.load(a.crossval)}

    def row(g):
        e, c = corp[g["name"]], cv[g["name"]]
        return features(e["starts"], c["starts"], c["probs"], g["line"], read_meta(a.meta, g["name"]),
                        e["strategy"], e["roles"][g["line"]])

    def fit(items):
        X, y = [], []
        for g in items:
            e, c = corp[g["name"]], cv[g["name"]]
            re_, rm = _right(g, e["starts"][g["line"]]), _right(g, c["starts"][g["line"]])
            if re_ != rm:
                X.append(row(g))
                y.append(int(re_))
        m = LogisticRegression(C=0.5, max_iter=2000).fit(np.array(X), np.array(y))
        return {"coef": [float(w) for w in m.coef_[0]], "intercept": float(m.intercept_[0])}, len(y)

    def pick(model, g):
        e, c = corp[g["name"]], cv[g["name"]]
        es, ms = e["starts"][g["line"]], c["starts"][g["line"]]
        if sorted(es) == sorted(ms):
            return ms
        return es if prefer_engine(model, row(g)) else ms

    def score(model, items):
        out = {"arbiter": 0, "model": 0, "engine": 0}
        for g in items:
            e, c = corp[g["name"]], cv[g["name"]]
            out["arbiter"] += _right(g, pick(model, g))
            out["model"] += _right(g, c["starts"][g["line"]])
            out["engine"] += _right(g, e["starts"][g["line"]])
        return out

    gold = A.load(A.GOLD)
    fold = lambda g: zlib.crc32(D.family(g["name"]).encode()) % 5  # noqa: E731
    tot = {"arbiter": 0, "model": 0, "engine": 0}
    for k in range(5):
        m, _ = fit([g for g in gold if fold(g) != k])
        for key, v in score(m, [g for g in gold if fold(g) == k]).items():
            tot[key] += v
    print("hand labels, out of fold (300): " + "  ".join(f"{k} {v}" for k, v in tot.items()))
    final, n = fit(gold)
    print(f"final arbiter: trained on {n} lines where exactly one of engine/model is right")
    if os.path.exists(A.TEST):
        test = [g for g in A.load(A.TEST) if g["name"] in cv]
        print(f"fresh test ({len(test)}): " + "  ".join(f"{k} {v}" for k, v in score(final, test).items()))
    if a.save:
        with open(a.save, "w", encoding="utf-8") as fh:
            json.dump(final, fh, indent=1)


if __name__ == "__main__":
    main()
