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
import json
import os
import sys

import zlib

import lightgbm as lgb
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extract", "model"))
import dataset as D  # noqa: E402
from features import JOIN_KIND, cand_rows, line_rows  # noqa: E402
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


CAND_PARAMS = dict(n_estimators=300, learning_rate=0.05, num_leaves=63, min_child_samples=10)


def train_cands(Xtr, ytr, w=None):
    m = lgb.LGBMClassifier(verbose=-1, **CAND_PARAMS)
    m.fit(Xtr, ytr, sample_weight=w)
    return m


def clean_masks(tr, Xr, yr, Xc, yc, kc, thresh):
    """Confident-learning style label cleaning on the training docs: predict
    each training row from models that did not see its family (3 inner
    folds) and mark for dropping the rows whose label the prediction
    contradicts with confidence >= 1-thresh. Those are mostly the engine's
    own mistakes. Returns (keep_roles, keep_starts) masks."""
    inner = {id(e): zlib.crc32((D.family(e["name"]) + "#inner").encode()) % 3 for e in tr}
    rfam = np.array([inner[id(e)] for e in tr for f, r, _ in line_rows(e) if r >= 0])
    cfam = np.array([inner[eid] for eid, _, _ in kc])
    keep_c = np.ones(len(yc), bool)
    keep_r = np.ones(len(yr), bool)
    for k in range(3):
        m = train_cands(Xc[cfam != k], yc[cfam != k])
        p = m.predict_proba(Xc[cfam == k])[:, 1]
        y = yc[cfam == k]
        bad = ((y == 1) & (p < thresh)) | ((y == 0) & (p > 1 - thresh))
        idx = np.where(cfam == k)[0]
        keep_c[idx[bad]] = False
        mr = train_roles(Xr[rfam != k], yr[rfam != k])
        pr = mr.predict_proba(Xr[rfam == k])
        yk = yr[rfam == k]
        badr = pr[np.arange(len(yk)), yk] < thresh
        idx = np.where(rfam == k)[0]
        keep_r[idx[badr]] = False
    return keep_r, keep_c


# _join_kind codes that mean "inside one timestamp": month+day, weekday+date,
# date+time, time+AM/PM/zone, time+year. (Number+unit is left alone: the
# engine is often right to split those.)
TIMESTAMP_JOINS = (1, 2, 3, 4, 7)


def load_hand(paths):
    """Hand-labelled lines -> {(name, line): starts} (the main answer)."""
    out = {}
    for path in paths or []:
        with open(path, encoding="utf-8") as fh:
            for ln in fh:
                if ln.strip():
                    g = json.loads(ln)
                    out[(g["name"], g["line"])] = g["starts"]
    return out


VALIDATED = os.path.join(os.path.dirname(HERE), "docs", "archive", "review-validated-cumulative.txt")


def load_validated(path=VALIDATED):
    """Tools whose output the maintainer reviewed and approved (the corpus
    review rounds, 2026-07/08)."""
    try:
        with open(path, encoding="utf-8") as fh:
            return {ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")}
    except OSError:
        return set()


def prepare(tr, clean_at=0.0, fix_labels=False, hand=None, hand_w=1.0, trusted=None,
            trusted_w=1.0, log=print):
    """Training arrays (roles X, y; starts X, y, sample weights), optionally
    with three label repairs:
      clean_at    drop labels that models trained on other families
                  contradict with confidence;
      fix_labels  drop engine field starts that sit inside a timestamp
                  (`12:30:01 | AM` is one value; the engine splits it in every
                  sar-family golden, so cleaning can't see it);
      hand        {(name, line): starts} hand labels that replace the
                  engine's on those lines, weighted hand_w and never cleaned;
      trusted     names of tools whose output a person approved: their
                  labels are never cleaned and are weighted trusted_w."""
    Xr, yr = role_xy(tr)
    Xc, yc, kc = cand_xy(tr)
    keep_r = np.ones(len(yr), bool)
    keep_c = np.ones(len(yc), bool)
    if clean_at:
        keep_r, keep_c = clean_masks(tr, Xr, yr, Xc, yc, kc, clean_at)
        log(f"cleaning dropped {int((~keep_r).sum())}/{len(yr)} role labels, "
            f"{int((~keep_c).sum())}/{len(yc)} start labels")
    wc = np.ones(len(yc), dtype=np.float32)
    if trusted:
        tdoc = {id(e) for e in tr if e["name"] in trusted}
        tc = np.array([eid in tdoc for eid, _, _ in kc])
        tr_rows = np.array([id(e) in tdoc for e in tr for f, r, _ in line_rows(e) if r >= 0])
        keep_c |= tc
        keep_r |= tr_rows
        wc[tc] = trusted_w
        log(f"{len(tdoc)} approved tools: {int(tc.sum())} start labels kept and weighted {trusted_w:g}")
    yc = yc.copy()
    if fix_labels:
        bad = np.isin(Xc[:, JOIN_KIND], TIMESTAMP_JOINS) & (yc == 1)
        yc[bad] = 0
        log(f"timestamp fix relabelled {int(bad.sum())} start labels")
    if hand:
        names = {id(e): e["name"] for e in tr}
        lines = set()
        for idx, (eid, j, i) in enumerate(kc):
            st = hand.get((names[eid], j))
            if st is not None:
                yc[idx] = 1 if i in st else 0
                wc[idx] = hand_w
                keep_c[idx] = True
                lines.add((eid, j))
        log(f"hand labels on {len(lines)} training lines (weight {hand_w:g})")
    return Xr[keep_r], yr[keep_r], Xc[keep_c], yc[keep_c], wc[keep_c]


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


def run(name, tag, train, tests, save=None, clean_at=0.0, fix_labels=False, hand=None, hand_w=1.0,
        trusted=None, trusted_w=1.0):
    print(f"\n## trained on {name} ({len(train)} docs)")
    Xr, yr, Xc, yc, wc = prepare(train, clean_at, fix_labels, hand, hand_w, trusted, trusted_w,
                                 log=lambda m: print("  " + m))
    rm, cm = train_roles(Xr, yr), train_cands(Xc, yc, wc)
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
    ap.add_argument("--clean", type=float, default=0.0,
                    help="drop training labels contradicted at this confidence (0.05 is the tested value)")
    ap.add_argument("--fix-labels", action="store_true",
                    help="drop engine field starts that fall inside a timestamp")
    ap.add_argument("--hand", nargs="*", default=[],
                    help="hand-labelled lines (jsonl, as ml/eval/gold-*.jsonl) to train on")
    ap.add_argument("--hand-weight", type=float, default=20.0)
    ap.add_argument("--trusted-weight", type=float, default=0.0,
                    help="weight for labels of maintainer-approved tools (0 = treat them like the rest)")
    ap.add_argument("--final", action="store_true",
                    help="train one model on the WHOLE corpus (no held-out test) and save it")
    a = ap.parse_args(argv)
    if a.final:
        everything = D.load(a.corpus)
        run("the whole corpus (final model)", "final", everything, [], save=a.save or
            os.path.join(HERE, "models"), clean_at=a.clean, fix_labels=a.fix_labels,
            hand=load_hand(a.hand), hand_w=a.hand_weight,
            trusted=load_validated() if a.trusted_weight else None, trusted_w=a.trusted_weight)
        return
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
    run("corpus-train only", "corpus", ctr, tests, save=a.save, clean_at=a.clean, fix_labels=a.fix_labels)
    run("corpus-train + synthetic", "mix", ctr + syn, tests, save=a.save)


if __name__ == "__main__":
    main()
