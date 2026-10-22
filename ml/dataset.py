# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Loading, the train/test split, scoring, and the rule baselines every model
is compared against. Stdlib only.

Split: corpus tools are grouped by family (the name up to the first - or _,
so docker-ps and docker-images go together) and a fixed fifth of families is
held out. Testing on unseen families, not unseen files, is what says whether
the model learned layouts rather than memorised tools.
"""
import json
import zlib

from layout import PREDICTED, candidates


def load(path):
    with open(path, encoding="utf-8") as fh:
        return [json.loads(ln) for ln in fh if ln.strip()]


def family(name):
    return name.split("-")[0].split("_")[0].lower()


def is_test(ex):
    return zlib.crc32(family(ex["name"]).encode()) % 5 == 0


def is_val(ex):
    """A tenth of the TRAINING families, for choosing epochs and settings
    without looking at the test families."""
    return zlib.crc32(family(ex["name"]).encode()) % 10 == 1


def split(examples):
    tr = [e for e in examples if not is_test(e)]
    te = [e for e in examples if is_test(e)]
    return tr, te


# -- scoring ---------------------------------------------------------------
def role_report(gold, pred):
    """gold/pred: lists of role indices into PREDICTED."""
    n = len(gold)
    acc = sum(g == p for g, p in zip(gold, pred)) / max(1, n)
    per = {}
    for k, name in enumerate(PREDICTED):
        tp = sum(1 for g, p in zip(gold, pred) if g == k and p == k)
        fp = sum(1 for g, p in zip(gold, pred) if g != k and p == k)
        fn = sum(1 for g, p in zip(gold, pred) if g == k and p != k)
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        per[name] = (f1, tp + fn)
    present = [f for f, sup in per.values() if sup]
    return {"n": n, "acc": acc, "macro_f1": sum(present) / max(1, len(present)), "per": per}


def lenient(gold, pred):
    """Role accuracy with row/kv as one class: a two-field `key  value` line
    is honestly either, depending on the shape the golden took."""
    row, kv = PREDICTED.index("row"), PREDICTED.index("kv")
    f = lambda x: row if x == kv else x  # noqa: E731
    return sum(f(g) == f(p) for g, p in zip(gold, pred)) / max(1, len(gold))


def bound_report(lines_gold, lines_pred):
    """Per line: sets of starts. Candidate-level F1 and whole-line exact match."""
    tp = fp = fn = exact = 0
    for g, p in zip(lines_gold, lines_pred):
        tp += len(g & p)
        fp += len(p - g)
        fn += len(g - p)
        exact += g == p
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    return {"lines": len(lines_gold), "exact": exact / max(1, len(lines_gold)),
            "f1": 2 * prec * rec / (prec + rec) if prec + rec else 0.0}


def fmt_roles(r, gold=None, pred=None):
    per = "  ".join(f"{k}={v[0]:.2f}" for k, v in r["per"].items() if v[1])
    len_ = f"  lenient {lenient(gold, pred):.3f}" if gold is not None else ""
    return f"acc {r['acc']:.3f}  macro-F1 {r['macro_f1']:.3f}   [{per}]  (n={r['n']}){len_}"


def fmt_bounds(r):
    return f"line-exact {r['exact']:.3f}  start-F1 {r['f1']:.3f}  (lines={r['lines']})"


# -- rule baselines --------------------------------------------------------
def rule_ws(line):
    """Split on every whitespace run (awk's default)."""
    return {i for k, i in enumerate(candidates(line)) if k == 0 or line[i - 1].isspace()}


def rule_gap2(line):
    """Split on 2+ spaces, a tab, or a , ; | delimiter (the usual heuristic)."""
    out = set()
    for k, i in enumerate(candidates(line)):
        g = 0
        while i - g - 1 >= 0 and line[i - g - 1] == " ":
            g += 1
        before = line[i - g - 1] if i - g - 1 >= 0 else ""
        if k == 0 or g >= 2 or line[i - 1] == "\t" or before in ",;|│┃║":
            out.add(i)
    return out


def gold_bounds(examples):
    """[(example, line_index, set_of_starts)] for every line with known starts."""
    return [(e, j, set(st)) for e in examples for j, st in enumerate(e["starts"]) if st]
