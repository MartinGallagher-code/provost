#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Whole-corpus comparison of the tree model with the engine, by 5-fold
cross-validation over tool families.

Every labelled corpus file is predicted by a model trained on the other four
fifths of the families, so no file is scored by a model that saw its family.
The labels are the engine's own (generic) output, so "agreement" here means
agreement with the engine; disagreements need an independent judge, which is
what --sample is for: it writes a blind A/B sheet (engine and model in random
order) of disagreeing lines with context.

Needs numpy + lightgbm. Usage:
    python3 ml/crossval.py [--corpus ml/data/corpus.jsonl]
        [--out ml/data/crossval.jsonl] [--sample N --sheet FILE --key FILE]
"""
import argparse
import json
import os
import random
import sys
from collections import Counter

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extract", "model"))
import adjudicated as ADJ  # noqa: E402
import dataset as D  # noqa: E402
import decode as DEC  # noqa: E402
import train_baseline as B  # noqa: E402
from features import cand_features, line_rows  # noqa: E402
from layout import PREDICTED, fields, is_blank  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
K = D.FOLDS
fold = D.fold


def predict_doc(rm, cm, ex, decoder=False):
    """(roles, starts, probs) for one document; probs is per line
    {position: p} for the lines whose fields are scored. With decoder, the
    starts of `row` blocks are re-decided as whole tables (decode.py)."""
    rows = line_rows(ex)
    roles = [("blank" if is_blank(ln) else None) for ln in ex["lines"]]
    if rows:
        P = rm.predict(np.array([f for f, _, _ in rows], dtype=np.float32))
        for (_, _, j), p in zip(rows, P):
            roles[j] = PREDICTED[int(p)]
    starts = [None] * len(ex["lines"])
    probs = [None] * len(ex["lines"])
    for j, st in enumerate(ex["starts"]):
        if not st:
            continue
        cf = cand_features(ex["lines"], j)
        P = cm.predict_proba(np.array([f for _, f in cf], dtype=np.float32))[:, 1]
        probs[j] = {i: float(q) for (i, _), q in zip(cf, P)}
        starts[j] = [i for (i, _), q in zip(cf, P) if q > 0.5]
    if decoder:
        for j, st in DEC.decode(ex["lines"], roles, probs).items():
            starts[j] = st
    return roles, starts, probs


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus.jsonl"))
    ap.add_argument("--train-corpus", help="learn from these labels instead (e.g. ml/data/corpus-llm.jsonl); "
                    "--corpus stays the engine reference everything is scored against")
    ap.add_argument("--extra", nargs="*", default=[],
                    help="extra training sets in every fold (synthetic/generated layouts: no corpus family)")
    ap.add_argument("--learner", choices=["trees", "grid"], default="trees",
                    help="grid: the axial-transformer GridNet (train_grid.py; needs torch)")
    ap.add_argument("--epochs", type=int, default=20, help="GridNet training epochs")
    ap.add_argument("--out", default=os.path.join(HERE, "data", "crossval.jsonl"))
    ap.add_argument("--sample", type=int, default=0, help="disagreeing lines to put on the blind sheet")
    ap.add_argument("--sheet", default=os.path.join(HERE, "data", "adjudicate.txt"))
    ap.add_argument("--key", default=os.path.join(HERE, "data", "adjudicate-key.json"))
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--clean", type=float, default=0.0,
                    help="drop training labels contradicted at this confidence (e.g. 0.05)")
    ap.add_argument("--fix-labels", action="store_true",
                    help="drop engine field starts that fall inside a timestamp (training only)")
    ap.add_argument("--hand", nargs="*", default=[],
                    help="hand-labelled lines to TRAIN on (only those in each fold's training families)")
    ap.add_argument("--hand-weight", type=float, default=20.0)
    ap.add_argument("--trusted-weight", type=float, default=0.0,
                    help="weight for labels of maintainer-approved tools (0 = treat them like the rest)")
    ap.add_argument("--cand-params", help="JSON overrides for the field-start model's LightGBM settings")
    ap.add_argument("--test", default=ADJ.TEST, help="the fresh hand-labelled test set (see adjudicated.py)")
    ap.add_argument("--decode", action="store_true", help="decide each table's columns once (decode.py)")
    ap.add_argument("--gold", default=ADJ.GOLD, help="hand-labelled lines (see adjudicated.py)")
    ap.add_argument("--adjudicated", default=ADJ.DEFAULT,
                    help="blind-judged disagreements to score against (see adjudicated.py)")
    a = ap.parse_args(argv)
    if a.cand_params:
        B.CAND_PARAMS.update(json.loads(a.cand_params))
    exs = D.load(a.corpus)
    train_exs = D.load(a.train_corpus) if a.train_corpus else exs
    extra = [e for p in a.extra for e in D.load(p)]
    hand = B.load_hand(a.hand)
    validated = B.load_validated()
    preds, probs = {}, {}
    for k in range(K):
        tr = [e for e in train_exs if fold(e) != k] + extra
        te = [e for e in exs if fold(e) == k]
        if a.learner == "grid":
            import train_grid as G
            gm = G.fit(tr, a.epochs, log=lambda m: print(f"  fold {k + 1}: {m}", file=sys.stderr))
        else:
            Xr, yr, Xc, yc, wc = B.prepare(tr, a.clean, a.fix_labels, hand, a.hand_weight,
                                           validated if a.trusted_weight else None, a.trusted_weight,
                                           log=lambda m: print(f"  fold {k + 1}: {m}", file=sys.stderr))
            rm, cm = B.train_roles(Xr, yr), B.train_cands(Xc, yc, wc)
        for e in te:
            if a.learner == "grid":
                r, st, pr = G.predict_doc(gm, e, a.decode, [bool(s) for s in e["starts"]])
            else:
                r, st, pr = predict_doc(rm, cm, e, a.decode)
            preds[e["name"]] = (r, st)
            probs[e["name"]] = pr
        print(f"fold {k + 1}/{K}: trained on {len(tr)}, predicted {len(te)}", file=sys.stderr)

    with open(a.out, "w", encoding="utf-8") as fh:
        for e in exs:
            r, s = preds[e["name"]]
            pr = [None if q is None else sorted(q.items()) for q in probs[e["name"]]]
            fh.write(json.dumps({"name": e["name"], "roles": r, "starts": s, "probs": pr}) + "\n")

    # agreement with the engine, overall and per strategy
    tot, per = Counter(), {}
    files_all_lines = 0
    for e in exs:
        r, s = preds[e["name"]]
        st = per.setdefault(e["strategy"], Counter())
        file_ok = True
        for j, ln in enumerate(e["lines"]):
            if is_blank(ln):
                continue
            ok_r = r[j] == e["roles"][j]
            tot["roles"] += 1
            tot["roles_ok"] += ok_r
            st["roles"] += 1
            st["roles_ok"] += ok_r
            if e["starts"][j]:
                ok_s = set(s[j]) == set(e["starts"][j])
                tot["split"] += 1
                tot["split_ok"] += ok_s
                st["split"] += 1
                st["split_ok"] += ok_s
                file_ok &= ok_s
            file_ok &= ok_r
        files_all_lines += file_ok
    print(f"\nWhole corpus, out-of-fold ({len(exs)} labelled files):")
    print(f"  line roles agree with the engine:   {tot['roles_ok']}/{tot['roles']} "
          f"= {tot['roles_ok'] / tot['roles']:.3f}")
    print(f"  line splits agree with the engine:  {tot['split_ok']}/{tot['split']} "
          f"= {tot['split_ok'] / tot['split']:.3f}")
    print(f"  files where every line agrees:      {files_all_lines}/{len(exs)} "
          f"= {files_all_lines / len(exs):.3f}")
    print("\n  by engine strategy (files >= 15): files  roles  splits")
    nfiles = Counter(e["strategy"] for e in exs)
    for name, c in sorted(per.items(), key=lambda kv: -nfiles[kv[0]]):
        if nfiles[name] < 15:
            continue
        sp = f"{c['split_ok'] / c['split']:.3f}" if c["split"] else "  -  "
        print(f"    {name:24} {nfiles[name]:5d}  {c['roles_ok'] / max(1, c['roles']):.3f}  {sp}")

    vt = Counter()
    for e in exs:
        if e["name"] not in validated:
            continue
        _, s = preds[e["name"]]
        for j, st in enumerate(e["starts"]):
            if st:
                vt["n"] += 1
                t = e["lines"][j]
                vt["ok"] += ADJ.canon(t, s[j]) == ADJ.canon(t, st)
        vt["files"] += 1
    if vt["n"]:
        print(f"\n  maintainer-approved tools ({vt['files']} files, {vt['n']} lines): "
              f"model splits match the approved output on {vt['ok'] / vt['n']:.3f}")

    if os.path.exists(a.test):
        test = [g for g in ADJ.load(a.test) if g["name"] in preds]
        eng = {e["name"]: e for e in exs}
        r, n = ADJ.gold_score(test, lambda g: preds[g["name"]][1][g["line"]])
        re_, _ = ADJ.gold_score(test, lambda g: eng[g["name"]]["starts"][g["line"]])
        print(f"\n  FRESH TEST lines (scored once): model {r}/{n} = {r / max(1, n):.3f}   "
              f"(engine {re_}/{n} = {re_ / max(1, n):.3f})")

    if os.path.exists(a.gold):
        gold = [g for g in ADJ.load(a.gold) if g["name"] in preds]
        r, n = ADJ.gold_score(gold, lambda g: preds[g["name"]][1][g["line"]])
        eng = {e["name"]: e for e in exs}
        re_, _ = ADJ.gold_score(gold, lambda g: eng[g["name"]]["starts"][g["line"]])
        print(f"\n  hand-labelled lines (gold): model {r}/{n} = {r / max(1, n):.3f}   "
              f"(engine {re_}/{n} = {re_ / max(1, n):.3f})")
        for src in ("random", "disagree"):
            sub = [g for g in gold if g["source"] == src]
            r, n = ADJ.gold_score(sub, lambda g: preds[g["name"]][1][g["line"]])
            re_, _ = ADJ.gold_score(sub, lambda g: eng[g["name"]]["starts"][g["line"]])
            print(f"    {src:9} lines: model {r}/{n} = {r / max(1, n):.3f}   "
                  f"engine {re_}/{n} = {re_ / max(1, n):.3f}")

    if os.path.exists(a.adjudicated):
        items = [it for it in ADJ.load(a.adjudicated) if it["name"] in preds]
        right, scored = ADJ.score(items, lambda it: preds[it["name"]][1][it["line"]] or [])
        eng, _ = ADJ.score(items, lambda it: it["engine"])
        print(f"\n  adjudicated hard lines (independent answer key): model {right}/{scored} "
              f"= {right / max(1, scored):.3f}   (engine {eng}/{scored} = {eng / max(1, scored):.3f})")

    if a.sample:
        dis = []
        for e in exs:
            _, s = preds[e["name"]]
            for j, st in enumerate(e["starts"]):
                if st and set(s[j]) != set(st):
                    dis.append((e, j, sorted(st), sorted(s[j])))
        rng = random.Random(a.seed)
        pick = rng.sample(dis, min(a.sample, len(dis)))
        key = []
        with open(a.sheet, "w", encoding="utf-8") as fh:
            for n, (e, j, eng, mod) in enumerate(pick, 1):
                swap = rng.random() < 0.5
                A, Bs = (mod, eng) if swap else (eng, mod)
                key.append({"item": n, "name": e["name"], "strategy": e["strategy"],
                            "A": "model" if swap else "engine"})
                lo, hi = max(0, j - 4), min(len(e["lines"]), j + 3)
                fh.write(f"### item {n}\ncontext:\n")
                for k2 in range(lo, hi):
                    fh.write(("  >> " if k2 == j else "     ") + "|" + e["lines"][k2] + "\n")
                line = e["lines"][j]
                fh.write("split A: " + " ¦ ".join(fields(line, A)) + "\n")
                fh.write("split B: " + " ¦ ".join(fields(line, Bs)) + "\n\n")
        with open(a.key, "w", encoding="utf-8") as fh:
            json.dump({"disagreeing_lines": len(dis), "items": key}, fh, indent=1)
        print(f"\n  {len(dis)} disagreeing lines; blind sheet of {len(pick)}: {a.sheet} (key: {a.key})")


if __name__ == "__main__":
    main()
