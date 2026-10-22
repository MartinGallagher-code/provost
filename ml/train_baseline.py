#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tree baseline: gradient-boosted trees (LightGBM) on hand-made features.

Trains the line-role and field-start models on corpus-train (+ synthetic),
then scores them on the held-out corpus families next to the rule baselines.
Needs numpy + lightgbm (ml/requirements.txt). Usage:

    python3 ml/train_baseline.py [--corpus ml/data/corpus.jsonl]
        [--synth ml/data/synth.jsonl] [--synth-test ml/data/synth-test.jsonl]
        [--save ml/models/]
"""
import argparse
import os
import sys

import lightgbm as lgb
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dataset as D  # noqa: E402
from features import cand_rows, line_rows  # noqa: E402
from layout import PREDICTED  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def role_xy(examples):
    X, y = [], []
    for e in examples:
        for f, r, _ in line_rows(e):
            if r >= 0:
                X.append(f)
                y.append(r)
    return np.array(X, dtype=np.float32), np.array(y)


def cand_xy(examples):
    X, y, key = [], [], []
    for e in examples:
        for f, lab, j, i in cand_rows(e):
            X.append(f)
            y.append(lab)
            key.append((id(e), j, i))
    return np.array(X, dtype=np.float32), np.array(y), key


def train_roles(Xtr, ytr):
    m = lgb.LGBMClassifier(n_estimators=300, learning_rate=0.05, num_leaves=31,
                           min_child_samples=10, class_weight="balanced", verbose=-1)
    m.fit(Xtr, ytr)
    return m


def train_cands(Xtr, ytr):
    m = lgb.LGBMClassifier(n_estimators=300, learning_rate=0.05, num_leaves=63,
                           min_child_samples=10, verbose=-1)
    m.fit(Xtr, ytr)
    return m


def score_bounds(model, examples):
    X, y, key = cand_xy(examples)
    pred = model.predict(X) if len(X) else []
    lines_p = {}
    for (eid, j, i), p in zip(key, pred):
        lines_p.setdefault((eid, j), set())
        if p:
            lines_p[(eid, j)].add(i)
    gold = D.gold_bounds(examples)
    return D.bound_report([g for _, _, g in gold],
                          [lines_p.get((id(e), j), set()) for e, j, _ in gold])


def score_rule(rule, examples):
    gold = D.gold_bounds(examples)
    return D.bound_report([g for _, _, g in gold], [rule(e["lines"][j]) for e, j, _ in gold])


def run(name, tag, train, tests, save=None):
    print(f"\n## trained on {name} ({len(train)} docs)")
    Xr, yr = role_xy(train)
    Xc, yc, _ = cand_xy(train)
    rm, cm = train_roles(Xr, yr), train_cands(Xc, yc)
    for tname, te in tests:
        Xt, yt = role_xy(te)
        g, p = list(yt), list(rm.predict(Xt))
        print(f"  {tname:13} roles   " + D.fmt_roles(D.role_report(g, p), g, p))
        print(f"  {tname:13} starts  " + D.fmt_bounds(score_bounds(cm, te)))
    if save:
        os.makedirs(save, exist_ok=True)
        for m, part in ((rm, "roles"), (cm, "starts")):
            path = os.path.join(save, f"baseline-{tag}-{part}.txt")
            m.booster_.save_model(path)
            print(f"  saved {path} ({os.path.getsize(path)} bytes)")
    return rm, cm


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus.jsonl"))
    ap.add_argument("--synth", default=os.path.join(HERE, "data", "synth.jsonl"))
    ap.add_argument("--synth-test", default=os.path.join(HERE, "data", "synth-test.jsonl"))
    ap.add_argument("--save", help="directory to write the trained boosters to")
    a = ap.parse_args(argv)
    ctr, cte = D.split(D.load(a.corpus))
    syn = D.load(a.synth)
    syn_te = D.load(a.synth_test) if os.path.exists(a.synth_test) else []
    tests = [("corpus-test", cte)] + ([("synth-test", syn_te)] if syn_te else [])
    print(f"corpus: {len(ctr)} train / {len(cte)} test docs (held-out families); synth: {len(syn)}")

    print("\n## rule baselines")
    for tname, te in tests:
        _, yt = role_xy(te)
        maj = int(np.bincount(role_xy(ctr)[1]).argmax())
        print(f"  {tname:13} roles   majority '{PREDICTED[maj]}': "
              + D.fmt_roles(D.role_report(list(yt), [maj] * len(yt))))
        print(f"  {tname:13} starts  split-on-whitespace: " + D.fmt_bounds(score_rule(D.rule_ws, te)))
        print(f"  {tname:13} starts  split-on-2+-spaces:  " + D.fmt_bounds(score_rule(D.rule_gap2, te)))

    run("synthetic only", "synth", syn, tests)
    run("corpus-train only", "corpus", ctr, tests, save=a.save)
    run("corpus-train + synthetic", "mix", ctr + syn, tests, save=a.save)


if __name__ == "__main__":
    main()
