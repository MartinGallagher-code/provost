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
import zlib
from collections import Counter

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dataset as D  # noqa: E402
import train_baseline as B  # noqa: E402
from features import cand_features, line_rows  # noqa: E402
from layout import PREDICTED, fields, is_blank  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
K = 5


def fold(ex):
    return zlib.crc32(D.family(ex["name"]).encode()) % K


def predict_doc(rm, cm, ex):
    rows = line_rows(ex)
    roles = [("blank" if is_blank(ln) else None) for ln in ex["lines"]]
    if rows:
        P = rm.predict(np.array([f for f, _, _ in rows], dtype=np.float32))
        for (_, _, j), p in zip(rows, P):
            roles[j] = PREDICTED[int(p)]
    starts = [None] * len(ex["lines"])
    for j, st in enumerate(ex["starts"]):
        if not st:
            continue
        cf = cand_features(ex["lines"], j)
        P = cm.predict(np.array([f for _, f in cf], dtype=np.float32))
        starts[j] = [i for (i, _), q in zip(cf, P) if q]
    return roles, starts


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus.jsonl"))
    ap.add_argument("--out", default=os.path.join(HERE, "data", "crossval.jsonl"))
    ap.add_argument("--sample", type=int, default=0, help="disagreeing lines to put on the blind sheet")
    ap.add_argument("--sheet", default=os.path.join(HERE, "data", "adjudicate.txt"))
    ap.add_argument("--key", default=os.path.join(HERE, "data", "adjudicate-key.json"))
    ap.add_argument("--seed", type=int, default=2026)
    a = ap.parse_args(argv)
    exs = D.load(a.corpus)
    preds = {}
    for k in range(K):
        tr = [e for e in exs if fold(e) != k]
        te = [e for e in exs if fold(e) == k]
        Xr, yr = B.role_xy(tr)
        Xc, yc, _ = B.cand_xy(tr)
        rm, cm = B.train_roles(Xr, yr), B.train_cands(Xc, yc)
        for e in te:
            preds[e["name"]] = predict_doc(rm, cm, e)
        print(f"fold {k + 1}/{K}: trained on {len(tr)}, predicted {len(te)}", file=sys.stderr)

    with open(a.out, "w", encoding="utf-8") as fh:
        for e in exs:
            r, s = preds[e["name"]]
            fh.write(json.dumps({"name": e["name"], "roles": r, "starts": s}) + "\n")

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
