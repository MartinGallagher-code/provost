#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""One cross-validation fold, scored against the LLM labels: the quick
development yardstick for comparing learners and training sets.

    python3 ml/fold_eval.py [--fold 0] [--learner trees|grid|both|lm]
        [--extra ml/data/gen.jsonl ...] [--epochs 9] [--hybrid]
        [--lm-load ml/models/lm/best] [--lm-base HuggingFaceTB/SmolLM2-135M]

Every learner trains on the LLM labels (ml/data/corpus-llm.jsonl) of the
other folds, plus any --extra sets (synthetic or generated layouts, which
belong to no corpus family). It predicts the held-out fold's documents and
reports how often each line's split matches the LLM label, on every line
where both the engine and the LLM see fields (thousands of lines; the LLM
labels are 98% right against the hand labels), plus the few gold lines in
the fold. With --learner both, the average of the two models' start
probabilities is scored too. --learner lm is the tiny pretrained language
model (train_lm.py): trained here for --lm-epochs, or a saved one scored with
--lm-load (train it with train_lm.py --fold N for a fair score). The fresh
hand-labelled test set is not read.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(os.path.dirname(HERE), "extract", "model"))
import adjudicated as ADJ  # noqa: E402
import crossval as CV  # noqa: E402
import dataset as D  # noqa: E402
import decode as DEC  # noqa: E402
import train_baseline as B  # noqa: E402


def starts_from(lines, roles, probs):
    st = [None if p is None else [c for c, q in p.items() if q > 0.5] for p in probs]
    for j, s in DEC.decode(lines, roles, probs).items():
        st[j] = s
    return st


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--fold", type=int, default=0)
    ap.add_argument("--learner", choices=["trees", "grid", "both", "lm"], default="both")
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus.jsonl"), help="engine labels")
    ap.add_argument("--llm", default=os.path.join(HERE, "data", "corpus-llm.jsonl"))
    ap.add_argument("--extra", nargs="*", default=[], help="extra training sets (any family-free layouts)")
    ap.add_argument("--extra-trees", action="store_true", help="give the trees the extra sets too")
    ap.add_argument("--epochs", type=int, default=9)
    ap.add_argument("--hybrid", action="store_true")
    ap.add_argument("--lm-load", help="a saved train_lm.py model (trained without this fold)")
    ap.add_argument("--lm-base", default=None, help="the LM to fine-tune (default: train_lm.BASE)")
    ap.add_argument("--lm-epochs", type=int, default=2)
    ap.add_argument("--limit", type=int, default=0, help="score only the first N held-out docs (a quick look)")
    a = ap.parse_args(argv)

    eng = {e["name"]: e for e in D.load(a.corpus) if CV.fold(e) == a.fold}
    if a.limit:
        eng = dict(list(eng.items())[: a.limit])
    llm_all = D.load(a.llm)
    llm = {e["name"]: e for e in llm_all}
    tr = [e for e in llm_all if CV.fold(e) != a.fold]
    extra = [e for p in a.extra for e in D.load(p)]
    print(f"fold {a.fold}: train {len(tr)} LLM-labelled docs + {len(extra)} extra; "
          f"score {len(eng)} held-out docs", file=sys.stderr)

    preds = {}
    if a.learner in ("trees", "both"):
        Xr, yr, Xc, yc, wc = B.prepare(tr + (extra if a.extra_trees else []), 0.0, False, [], 0, None, 0,
                                       log=lambda m: print("  trees: " + m, file=sys.stderr))
        rm, cm = B.train_roles(Xr, yr), B.train_cands(Xc, yc, wc)
        preds["trees"] = {n: CV.predict_doc(rm, cm, e) for n, e in eng.items()}
    if a.learner in ("grid", "both"):
        import torch
        import train_grid as G
        torch.set_num_threads(os.cpu_count() or 1)
        gm = G.fit(tr, a.epochs, synth=extra, hybrid=a.hybrid,
                   log=lambda m: print("  grid: " + m, file=sys.stderr))
        preds["grid"] = {n: G.predict_doc(gm, e, False, [bool(s) for s in e["starts"]])
                         for n, e in eng.items()}
    if a.learner == "lm":
        import torch
        import train_lm as LM
        torch.set_num_threads(os.cpu_count() or 1)
        if a.lm_load:
            lm, enc = LM.load(a.lm_load)
            print(f"  lm: loaded {a.lm_load} ({lm.meta})", file=sys.stderr)
        else:
            lm, enc = LM.fit(tr, a.lm_epochs, base=a.lm_base or LM.BASE, extra=extra,
                             log=lambda m: print("  lm: " + m, file=sys.stderr))
        preds["lm"] = {n: LM.predict_doc(lm, enc, e) for n, e in eng.items()}

    out = {}
    for k, P in preds.items():
        out[k] = {n: starts_from(eng[n]["lines"], r, pr) for n, (r, _, pr) in P.items()}
    if set(preds) == {"trees", "grid"}:
        out["avg"] = {}
        for n, e in eng.items():
            pt, pg = preds["trees"][n][2], preds["grid"][n][2]
            avg = [None if (x is None or y is None) else {c: (x[c] + y.get(c, 0.0)) / 2 for c in x}
                   for x, y in zip(pt, pg)]
            out["avg"][n] = starts_from(e["lines"], preds["grid"][n][0], avg)
    out["engine"] = {n: e["starts"] for n, e in eng.items()}

    tot, n = {k: 0 for k in out}, 0
    gold = {(g["name"], g["line"]): g for g in ADJ.load(ADJ.GOLD)}
    gtot, gn = {k: 0 for k in out}, 0
    for name, e in eng.items():
        L = llm.get(name)
        if not L or L["lines"] != e["lines"]:
            continue
        for j, t in enumerate(e["lines"]):
            if not e["starts"][j] or not L["starts"][j]:
                continue
            n += 1
            want = ADJ.canon(t, L["starts"][j])
            for k in out:
                tot[k] += ADJ.canon(t, out[k][name][j] or []) == want
            g = gold.get((name, j))
            if g:
                gn += 1
                for k in out:
                    gtot[k] += ADJ.gold_score([g], lambda _: out[k][name][j] or [])[0]
    print(f"fold {a.fold}, {n} held-out lines, split matches the LLM label:")
    for k in out:
        print(f"  {k:7} {tot[k]:5d}/{n} = {tot[k] / max(1, n):.3f}   gold {gtot[k]}/{gn}")


if __name__ == "__main__":
    main()
