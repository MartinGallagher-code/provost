#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""The arbiter: on a line where the engine's split and the model's differ,
which one to trust.

The two are right on different lines, so a small logistic regression picks
per line. Inputs (extract/model/arbitrate.py, shared with capture time):

  * how likely each split is under the model's own per-candidate
    probabilities (log-likelihood of the engine's split, of the model's,
    and their difference);
  * each split's field count, and how often neighbouring lines have the
    same count under it (a split that keeps the table consistent);
  * the engine's own confidence, line coverage and column consistency for
    the capture (--emit-meta), whether it was aligned-columns, and
    whether the line is key/value.

With the LM's role probabilities in the fold files (fold_eval.py --out
keeps them), a second part is fitted the same way, always to the LLM labels
(the hand labels are splits only): "roles", for lines one reader calls a
header and the other a data row (a data line taken as the header renames
every column after it). It is left out when the folds give fewer than
MIN_ROLE_ROWS lines to fit it on.

It is fitted on out-of-fold predictions: each document's probabilities come
from a model that never trained on its family, so they are as sure of
themselves as the shipped model is on a capture it has never seen. Two
answer keys can say which split is right:

  * --target gold: the 300 hand-labelled lines (ml/eval/gold-*.jsonl). The
    trees' arbiter (arbiter.json) was fitted on these.
  * --target llm: the LLM labels of the whole corpus (ml/data/corpus-llm.jsonl),
    on every line where exactly one of the two splits agrees with the label:
    thousands of lines where the hand labels give a few dozen.

Its own score is nested: for each family fold the arbiter is fitted on the
other four and scored on that one, against the LLM labels (every line the
fold_eval.py yardstick counts), the hand labels, and per capture (how many
captures where the engine's split beat the model's it rescues, and how many
it makes worse). --threshold auto picks, inside each outer fold and from the
other folds only, the least probability that switches a line to the engine.

Needs numpy + scikit-learn to fit; the result is a handful of coefficients,
applied in plain Python.

    # the trees (2026-10-23): crossval.py --out, hand labels
    python3 ml/arbiter.py --crossval ml/data/crossval.jsonl --meta DIR --save extract/model/arbiter.json
    # the tiny LM (PV-012): fold_eval.py --learner lm --out, one file a fold
    python3 ml/arbiter.py --crossval ml/data/oof-lm-f*.jsonl --meta DIR --target llm \\
        --threshold auto --for-model provost-model --save extract/model/arbiter-lm.json
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extract", "model"))
import adjudicated as A  # noqa: E402
import dataset as D  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
THRESHOLDS = (0.5, 0.6, 0.7, 0.8, 0.9)
MIN_ROLE_ROWS = 20


# The feature code is shared with the capture-time runtime, so training and
# use can't drift apart.
from arbitrate import (features, loglik, p_engine, prefer_engine,  # noqa: E402,F401
                       role_contested, role_features)


def read_meta(meta_dir, name):
    try:
        with open(os.path.join(meta_dir, name + ".meta"), encoding="utf-8") as fh:
            f = fh.readline().rstrip("\n").split("\t")
        return [float(x) if x not in ("-", "") else -1.0 for x in f[2:5]]
    except (OSError, ValueError):
        return [-1.0, -1.0, -1.0]


def _right(g, split):
    """Is split right for hand-labelled line g (its main answer or its
    acceptable alternative)?"""
    t = g["text"]
    p = A.canon(t, split)
    return p == A.canon(t, g["starts"]) or (g["alt"] is not None and p == A.canon(t, g["alt"]))


def _same(a, b):
    return sorted(a or []) == sorted(b or [])


class Data:
    """The documents an arbiter is fitted and scored on: the engine's split
    (corpus.jsonl), the model's out-of-fold one with its probabilities, the
    capture's engine meta, and the two answer keys."""

    def __init__(self, corpus, crossval, meta_dir, llm=None, gold=None):
        self.corp = {e["name"]: e for e in corpus}
        self.cv = {e["name"]: e for e in crossval if e["name"] in self.corp}
        self.llm = {e["name"]: e for e in (llm or [])}
        self.gold = [g for g in (gold or []) if g["name"] in self.cv]
        self.meta_dir = meta_dir
        self._meta, self._probs, self._llm_lines = {}, {}, {}

    @staticmethod
    def fold(name):
        return D.fold({"name": name})

    def meta(self, name):
        if name not in self._meta:
            self._meta[name] = read_meta(self.meta_dir, name) if self.meta_dir else [-1.0, -1.0, -1.0]
        return self._meta[name]

    def probs(self, name):
        if name not in self._probs:
            self._probs[name] = [None if p is None else [(int(x), float(q)) for x, q in p]
                                 for p in self.cv[name]["probs"]]
        return self._probs[name]

    def contested(self, name, j):
        """True where capture time would arbitrate line j: both splits
        exist, they differ, and the model scored the line."""
        e, c = self.corp[name], self.cv[name]
        es, ms = e["starts"][j], c["starts"][j]
        return bool(es) and bool(ms) and not _same(es, ms) and c["probs"][j] is not None

    def row(self, name, j):
        e, c = self.corp[name], self.cv[name]
        es = [s or [] for s in e["starts"]]
        ms = [s or [] for s in c["starts"]]
        return features(es, ms, self.probs(name), j, self.meta(name), e["strategy"], e["roles"][j])

    def has_roles(self):
        return any(c.get("rprobs") for c in self.cv.values())

    def role_contested(self, name, j):
        e, c = self.corp[name], self.cv[name]
        rp = c.get("rprobs") or [None] * len(c["roles"])
        return role_contested(e["roles"], c["roles"], rp, j)

    def role_row(self, name, j):
        e, c = self.corp[name], self.cv[name]
        return role_features(e["lines"], e["roles"], c["roles"], c["rprobs"], j, self.meta(name), e["strategy"])

    def llm_roles(self, name):
        """The LLM label's roles, or None when its lines differ."""
        e, L = self.corp[name], self.llm.get(name)
        return L.get("roles") if L and L["lines"] == e["lines"] else None

    def llm_lines(self, name):
        """[(j, wanted canon)] for the lines the fold_eval.py yardstick counts:
        both the engine and the LLM label see fields."""
        if name not in self._llm_lines:
            e, L = self.corp[name], self.llm.get(name)
            self._llm_lines[name] = [] if not L or L["lines"] != e["lines"] else [
                (j, A.canon(t, L["starts"][j])) for j, t in enumerate(e["lines"])
                if e["starts"][j] and L["starts"][j]]
        return self._llm_lines[name]


def training_rows(data, names, target):
    """(X, y): y = 1 where the engine's split is the right one, on the
    contested lines of these documents where exactly one of the two is."""
    X, y = [], []
    if target == "gold":
        for g in data.gold:
            n, j = g["name"], g["line"]
            if n not in names or not data.contested(n, j):
                continue
            re_ = _right(g, data.corp[n]["starts"][j])
            rm = _right(g, data.cv[n]["starts"][j])
            if re_ != rm:
                X.append(data.row(n, j))
                y.append(int(re_))
        return X, y
    for n in sorted(names):
        e, c = data.corp[n], data.cv[n]
        for j, want in data.llm_lines(n):
            if not data.contested(n, j):
                continue
            t = e["lines"][j]
            re_, rm = A.canon(t, e["starts"][j]) == want, A.canon(t, c["starts"][j]) == want
            if re_ != rm:
                X.append(data.row(n, j))
                y.append(int(re_))
    return X, y


def role_rows(data, names, target=None):
    """(X, y) for the roles part: y = 1 where the engine's role is the LLM
    label's, on the header/row disputes where exactly one reader's is."""
    X, y = [], []
    for n in sorted(names):
        want = data.llm_roles(n)
        if not want:
            continue
        e, c = data.corp[n], data.cv[n]
        for j in range(len(e["lines"])):
            if not data.role_contested(n, j):
                continue
            re_, rm = e["roles"][j] == want[j], c["roles"][j] == want[j]
            if re_ != rm:
                X.append(data.role_row(n, j))
                y.append(int(re_))
    return X, y


NEVER = {"coef": [0.0] * 13, "intercept": -30.0}     # a split part with nothing to learn from: no switch


def fit_splits(X, y):
    """The split part, or NEVER when the lines hold only one answer."""
    return fit_lr(X, y) if len(set(y)) == 2 else dict(NEVER)


def fit_lr(X, y, C=0.5):
    import numpy as np
    from sklearn.linear_model import LogisticRegression
    m = LogisticRegression(C=C, max_iter=5000).fit(np.array(X, dtype=float), np.array(y))
    return {"coef": [float(w) for w in m.coef_[0]], "intercept": float(m.intercept_[0])}


def choose_threshold(data, names, target, folds, rows=None):
    """The threshold that keeps the most lines right on these documents,
    each scored by an arbiter fitted on the others (an inner fold split).
    Ties go to the higher threshold: fewer switches. rows: training_rows
    (the splits) or role_rows."""
    rows = rows or training_rows
    gain = {t: 0 for t in THRESHOLDS}
    for k in folds:
        X, y = rows(data, {n for n in names if data.fold(n) != k}, target)
        if len(set(y)) < 2:
            continue
        m = fit_lr(X, y)
        Xt, yt = rows(data, {n for n in names if data.fold(n) == k}, target)
        for f, want_engine in zip(Xt, yt):
            p = p_engine(m, f)
            for t in THRESHOLDS:
                if p > t:
                    gain[t] += 1 if want_engine else -1
    return max(THRESHOLDS, key=lambda t: (gain[t], t))


def fit_roles(data, names, threshold, folds):
    """The roles part fitted on these documents, or None when there are too
    few disputes to fit it on."""
    X, y = role_rows(data, names)
    if len(y) < MIN_ROLE_ROWS or len(set(y)) < 2:
        return None
    m = fit_lr(X, y)
    m["threshold"] = (choose_threshold(data, names, None, folds, role_rows)
                      if threshold == "auto" else float(threshold))
    return m


def pick_role(model, data, n, j):
    """The role the arbiter keeps for line j of document n."""
    e, c = data.corp[n], data.cv[n]
    rm = model.get("roles") if model else None
    if rm and data.role_contested(n, j) and prefer_engine(rm, data.role_row(n, j)):
        return e["roles"][j]
    return c["roles"][j]


def pick(model, data, n, j):
    """The split the arbiter keeps for line j of document n."""
    es, ms = data.corp[n]["starts"][j], data.cv[n]["starts"][j]
    if model is None or not data.contested(n, j):
        return ms
    return es if prefer_engine(model, data.row(n, j)) else ms


def score(model, data, names):
    """Counts for one arbiter on these documents: lines right against the
    LLM labels and the hand labels for engine / model / arbiter, lines
    switched (and how many of those the switch made right or wrong), and
    captures: engine-better ones (more LLM-label lines right with the
    engine's split than the model's), how many of those the arbiter brings
    level with the engine or better (rescued), and captures it makes better
    or worse than the model alone."""
    out = {k: 0 for k in ("lines", "engine", "model", "arbiter", "gold", "gold_engine", "gold_model",
                          "gold_arbiter", "switched", "switched_right", "switched_wrong",
                          "docs", "engine_better", "rescued", "helped", "hurt",
                          "role_disputes", "role_engine", "role_model", "role_arbiter",
                          "role_switched", "role_switched_right", "role_switched_wrong")}
    out["rescued_names"], out["hurt_names"], out["role_rescued_names"] = [], [], []
    for n in sorted(names):
        want = data.llm_roles(n)
        if want:
            for j in range(len(want)):
                if not data.role_contested(n, j):
                    continue
                e_r, m_r, a_r = data.corp[n]["roles"][j], data.cv[n]["roles"][j], pick_role(model, data, n, j)
                out["role_disputes"] += 1
                out["role_engine"] += e_r == want[j]
                out["role_model"] += m_r == want[j]
                out["role_arbiter"] += a_r == want[j]
                if a_r != m_r:
                    out["role_switched"] += 1
                    out["role_switched_right"] += a_r == want[j]
                    out["role_switched_wrong"] += m_r == want[j]
                    if a_r == want[j] and n not in out["role_rescued_names"]:
                        out["role_rescued_names"].append(n)
    for n in sorted(names):
        e, c = data.corp[n], data.cv[n]
        lines = data.llm_lines(n)
        de = dm = da = 0
        for j, want in lines:
            t = e["lines"][j]
            a = pick(model, data, n, j)
            ok_e, ok_m, ok_a = (A.canon(t, s) == want for s in (e["starts"][j], c["starts"][j], a))
            out["lines"] += 1
            out["engine"] += ok_e
            out["model"] += ok_m
            out["arbiter"] += ok_a
            de, dm, da = de + ok_e, dm + ok_m, da + ok_a
            if not _same(a, c["starts"][j]):
                out["switched"] += 1
                out["switched_right"] += ok_a and not ok_m
                out["switched_wrong"] += ok_m and not ok_a
        if not lines:
            continue
        out["docs"] += 1
        if de > dm:
            out["engine_better"] += 1
            if da >= de:
                out["rescued"] += 1
                out["rescued_names"].append(n)
        out["helped"] += da > dm
        if da < dm:
            out["hurt"] += 1
            out["hurt_names"].append(n)
    for g in data.gold:
        if g["name"] not in names:
            continue
        n, j = g["name"], g["line"]
        out["gold"] += 1
        out["gold_engine"] += _right(g, data.corp[n]["starts"][j])
        out["gold_model"] += _right(g, data.cv[n]["starts"][j])
        out["gold_arbiter"] += _right(g, pick(model, data, n, j))
    return out


def add(tot, s):
    for k, v in s.items():
        tot[k] = tot.get(k, [] if isinstance(v, list) else 0) + v
    return tot


def nested(data, target, threshold):
    """Fit on four folds, score the fifth, for every fold: the arbiter's
    out-of-fold score, and per fold [(fold, threshold, training lines, score)]."""
    names = set(data.cv)
    folds = sorted({data.fold(n) for n in names})
    tot, per = {}, []
    for k in folds:
        tr = {n for n in names if data.fold(n) != k}
        te = {n for n in names if data.fold(n) == k}
        X, y = training_rows(data, tr, target)
        m = fit_splits(X, y)
        m["threshold"] = (choose_threshold(data, tr, target, [f for f in folds if f != k])
                          if threshold == "auto" else float(threshold))
        if data.has_roles():
            m["roles"] = fit_roles(data, tr, threshold, [f for f in folds if f != k])
        s = score(m, data, te)
        per.append((k, m["threshold"], len(y), s))
        add(tot, s)
    return tot, per


def report(name, s):
    n = max(1, s["lines"])
    return (f"{name}: {s['lines']} lines vs the LLM labels: engine {s['engine']} ({s['engine'] / n:.3f})  "
            f"model {s['model']} ({s['model'] / n:.3f})  arbiter {s['arbiter']} ({s['arbiter'] / n:.3f}); "
            f"switched {s['switched']} ({s['switched_right']} made right, {s['switched_wrong']} made wrong)\n"
            f"  hand labels {s['gold']}: engine {s['gold_engine']}  model {s['gold_model']}  "
            f"arbiter {s['gold_arbiter']}\n"
            f"  captures {s['docs']}: engine-better {s['engine_better']}, rescued {s['rescued']}; "
            f"arbiter better than the model on {s['helped']}, worse on {s['hurt']}\n"
            f"  header/row disputes {s['role_disputes']}: engine {s['role_engine']}  model {s['role_model']}  "
            f"arbiter {s['role_arbiter']}; switched {s['role_switched']} ({s['role_switched_right']} made right, "
            f"{s['role_switched_wrong']} made wrong)")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus.jsonl"))
    ap.add_argument("--crossval", nargs="+", default=[os.path.join(HERE, "data", "crossval.jsonl")],
                    help="out-of-fold predictions with probs (crossval.py --out, or fold_eval.py --out per fold)")
    ap.add_argument("--llm", default=os.path.join(HERE, "data", "corpus-llm.jsonl"), help="the LLM labels")
    ap.add_argument("--meta", required=True, help="dir of <tool>.meta (engine --emit-meta)")
    ap.add_argument("--target", choices=["gold", "llm"], default="gold",
                    help="the answer key the arbiter is fitted to (both are scored)")
    ap.add_argument("--threshold", default="0.5",
                    help="p(engine) above which a line keeps the engine's split, or auto (nested)")
    ap.add_argument("--for-model", default="",
                    help="what the arbiter is fitted for, recorded in --save; provost-model records the "
                         "installed provost_model package's version and fingerprint, so capture time "
                         "applies it to that model and no other")
    ap.add_argument("--show", type=int, default=0, help="list up to N rescued and N worse captures")
    ap.add_argument("--save", help="write the final coefficients (JSON) here")
    a = ap.parse_args(argv)
    crossval = [e for p in a.crossval for e in D.load(p)]
    llm = D.load(a.llm) if os.path.exists(a.llm) else []
    data = Data(D.load(a.corpus), crossval, a.meta, llm, A.load(A.GOLD))
    print(f"{len(data.cv)} documents with out-of-fold predictions, {len(data.gold)} hand-labelled lines; "
          f"fitted to the {a.target} labels")
    tot, per = nested(data, a.target, a.threshold)
    for k, t, n, s in per:
        print(f"fold {k} (threshold {t}, fitted on {n} lines): " + report("held out", s).split("\n")[0])
    print(report("all folds, out of fold", tot))
    if a.show:
        print("  rescued: " + " ".join(tot["rescued_names"][: a.show]))
        print("  worse:   " + " ".join(tot["hurt_names"][: a.show]))
        print("  header/row put right: " + " ".join(tot["role_rescued_names"][: a.show]))
    X, y = training_rows(data, set(data.cv), a.target)
    final = fit_splits(X, y)
    final["threshold"] = (choose_threshold(data, set(data.cv), a.target, sorted({data.fold(n) for n in data.cv}))
                          if a.threshold == "auto" else float(a.threshold))
    print(f"final arbiter: fitted on {len(y)} lines where exactly one of engine/model is right; "
          f"threshold {final['threshold']}")
    if data.has_roles():
        folds = sorted({data.fold(n) for n in data.cv})
        rm = fit_roles(data, set(data.cv), a.threshold, folds)
        if rm:
            final["roles"] = rm
            print(f"  roles part: fitted on {len(role_rows(data, set(data.cv))[1])} header/row disputes; "
                  f"threshold {rm['threshold']}")
        else:
            print(f"  roles part: left out (fewer than {MIN_ROLE_ROWS} header/row disputes to fit on)")
    if a.save:
        if a.for_model == "provost-model":
            import arbitrate
            import provost_model
            final["model"] = arbitrate.fingerprint(provost_model.MODEL_DIR)
            final["for"] = f"provost-model {provost_model.__version__}"
        elif a.for_model:
            final["for"] = a.for_model
        final["fitted"] = {"target": a.target, "lines": len(y), "documents": len(data.cv),
                           "out_of_fold": {k: tot[k] for k in (
                               "lines", "engine", "model", "arbiter", "gold", "gold_engine", "gold_model",
                               "gold_arbiter", "docs", "engine_better", "rescued", "helped", "hurt",
                               "role_disputes", "role_engine", "role_model", "role_arbiter")}}
        with open(a.save, "w", encoding="utf-8") as fh:
            json.dump(final, fh, indent=1)
            fh.write("\n")


if __name__ == "__main__":
    main()
