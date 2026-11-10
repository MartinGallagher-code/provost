#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""One cross-validation fold, scored against the LLM labels: the quick
development yardstick for comparing learners and training sets.

    python3 ml/fold_eval.py [--fold 0] [--learner trees|grid|both|lm]
        [--extra ml/data/gen.jsonl ...] [--epochs 9] [--hybrid]
        [--lm-load ml/models/lm/best] [--lm-base HuggingFaceTB/SmolLM2-135M]
        [--out ml/data/oof-lm-f0.jsonl]

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

--out FILE keeps the held-out predictions, one JSON line per document in
crossval.py --out's shape (name, roles, decoded starts, start probabilities
as [offset, p] pairs per line): the learner's own (lm, grid, or the trees
for --learner trees/both). Five folds' files together are out-of-fold
predictions for the whole corpus, which is what ml/arbiter.py is fitted on.

LightGBM and torch never share a process. Each bundles its own OpenMP
runtime, and on macOS the two copies of libomp in one process crash it
(exit 139). When a run needs both (--learner both, or lm with --lm-trees),
the torch learner trains in a child process of its own, started fresh
(spawn), and the trees train here.
"""
import argparse
import json
import multiprocessing
import os
import sys
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(os.path.dirname(HERE), "extract", "model"))
# Nothing here loads LightGBM or torch: each learner imports its own, so a
# process that needs only one never has the other (see run_learners).
import adjudicated as ADJ  # noqa: E402
import dataset as D  # noqa: E402
import decode as DEC  # noqa: E402

TORCH = ("grid", "lm")  # the learners that load torch; "trees" loads LightGBM


def starts_from(lines, roles, probs):
    st = [None if p is None else [c for c, q in p.items() if q > 0.5] for p in probs]
    for j, s in DEC.decode(lines, roles, probs).items():
        st[j] = s
    return st


def load(a):
    """(held-out engine docs by name, LLM-labelled training docs, extra
    training docs) for a's fold."""
    eng = {e["name"]: e for e in D.load(a.corpus) if D.fold(e) == a.fold}
    if a.limit:
        eng = dict(list(eng.items())[: a.limit])
    tr = [e for e in D.load(a.llm) if D.fold(e) != a.fold]
    extra = [e for p in a.extra for e in D.load(p)]
    return eng, tr, extra


def learners(a):
    """The learners a run trains, in the order they train."""
    ks = []
    if a.learner in ("trees", "both") or (a.learner == "lm" and a.lm_trees):
        ks.append("trees")
    if a.learner in ("grid", "both"):
        ks.append("grid")
    if a.learner == "lm":
        ks.append("lm")
    return ks


def plan(ks):
    """[(learner, in_child)]: a torch learner trains in a child process
    whenever the trees (LightGBM) train in this one."""
    mixed = "trees" in ks and any(k in TORCH for k in ks)
    return [(k, mixed and k in TORCH) for k in ks]


def in_child(fn, *args):
    """fn(*args) in a fresh interpreter (spawn, never fork: a forked child
    would inherit this process's libomp). The child re-imports this module,
    which loads neither LightGBM nor torch; fn must be a module-level
    function and its result picklable."""
    with ProcessPoolExecutor(1, mp_context=multiprocessing.get_context("spawn")) as ex:
        return ex.submit(fn, *args).result()


def run_learners(a, data):
    """{learner: {doc name: (roles, starts, probs)}} for every learner a asks
    for, LightGBM and torch kept in separate processes."""
    preds = {}
    for k, child in plan(learners(a)):
        preds[k] = in_child(predict_fold, k, a) if child else predict(k, a, *data)
    return preds


def predict_fold(k, a):
    """predict() with the fold loaded here: the child process's entry point."""
    return predict(k, a, *load(a))


def predict(k, a, eng, tr, extra):
    """Train learner k on tr (+ extra) and predict every held-out doc."""
    if k == "trees":
        import crossval as CV
        import train_baseline as B
        Xr, yr, Xc, yc, wc = B.prepare(tr + (extra if a.extra_trees else []), 0.0, False, [], 0, None, 0,
                                       log=lambda m: print("  trees: " + m, file=sys.stderr))
        rm, cm = B.train_roles(Xr, yr), B.train_cands(Xc, yc, wc)
        return {n: CV.predict_doc(rm, cm, e) for n, e in eng.items()}
    import torch
    torch.set_num_threads(a.threads)
    if k == "grid":
        import train_grid as G
        gm = G.fit(tr, a.epochs, synth=extra, hybrid=a.hybrid,
                   log=lambda m: print("  grid: " + m, file=sys.stderr))
        return {n: G.predict_doc(gm, e, False, [bool(s) for s in e["starts"]]) for n, e in eng.items()}
    import train_lm as LM
    if a.lm_load:
        lm, enc = LM.load(a.lm_load)
        print(f"  lm: loaded {a.lm_load} ({lm.meta})", file=sys.stderr)
    else:
        lm, enc = LM.fit(tr, a.lm_epochs, base=a.lm_base or LM.BASE, extra=extra,
                         log=lambda m: print("  lm: " + m, file=sys.stderr))
    return {n: LM.predict_doc(lm, enc, e) for n, e in eng.items()}


def out_learner(a):
    """The learner whose predictions --out keeps."""
    return {"both": "trees"}.get(a.learner, a.learner)


def write_out(path, eng, preds, out, k):
    """One JSON line per held-out document: crossval.py --out's shape."""
    with open(path, "w", encoding="utf-8") as fh:
        for n in eng:
            roles, _, probs = preds[k][n]
            pr = [None if q is None else sorted([int(c), float(p)] for c, p in q.items()) for q in probs]
            st = [None if s is None else sorted(s) for s in out[k][n]]
            fh.write(json.dumps({"name": n, "roles": roles, "starts": st, "probs": pr}) + "\n")


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
    ap.add_argument("--lm-trees", action="store_true",
                    help="with --learner lm: also train the trees and score the average of the two")
    ap.add_argument("--threads", type=int, default=os.cpu_count() or 1, help="torch threads")
    ap.add_argument("--out", help="write the learner's held-out predictions here (JSON lines)")
    ap.add_argument("--show", nargs=2, metavar=("LEARNER", "N"),
                    help="print N held-out lines where LEARNER's split differs from the LLM label")
    a = ap.parse_args(argv)

    data = load(a)
    eng = data[0]
    print(f"fold {a.fold}: train {len(data[1])} LLM-labelled docs + {len(data[2])} extra; "
          f"score {len(eng)} held-out docs", file=sys.stderr)
    preds = run_learners(a, data)
    llm = {e["name"]: e for e in D.load(a.llm)}

    out = {}
    for k, P in preds.items():
        out[k] = {n: starts_from(eng[n]["lines"], r, pr) for n, (r, _, pr) in P.items()}
    pair = ("grid" if "grid" in preds else "lm") if "trees" in preds else None
    if pair in preds:
        out["avg"] = {}
        for n, e in eng.items():
            pt, pg = preds["trees"][n][2], preds[pair][n][2]
            avg = [None if (x is None or y is None) else {c: (x[c] + y.get(c, 0.0)) / 2 for c in x}
                   for x, y in zip(pt, pg)]
            out["avg"][n] = starts_from(e["lines"], preds[pair][n][0], avg)
    out["engine"] = {n: e["starts"] for n, e in eng.items()}
    if a.out:
        write_out(a.out, eng, preds, out, out_learner(a))

    shown, show_k, show_n = 0, *(a.show if a.show else (None, 0))
    show_n = int(show_n)
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
            if show_k in out and shown < show_n and ADJ.canon(t, out[show_k][name][j] or []) != want:
                shown += 1
                cut = lambda st: " | ".join(t[x:y].strip() for x, y in zip(st, list(st[1:]) + [len(t)]))  # noqa: E731
                print(f"  {name}:{j}\n    label {cut(sorted(L['starts'][j]))}\n    {show_k:5} "
                      f"{cut(sorted(out[show_k][name][j] or []))}", file=sys.stderr)
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
