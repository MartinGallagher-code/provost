#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""The adjudicated set: lines where the engine and the model disagreed,
judged blind by independent reviewers. It is the one answer key here that
does not come from the engine, so it is how model changes are scored.

  build   turn crossval.py's blind sheet key + the reviewers' verdict TSVs
          into ml/eval/adjudicated-<date>.jsonl (committed: it is the work of
          the review, not regenerable)
  score   (library) accuracy of predicted splits against it

Each record: name, line index, line text, the engine's starts, the model's
starts at review time, the verdict (engine | model | both | neither) and the
reviewer's reason. A prediction is right when it equals an acceptable split
(the winner's, or either for `both`); `neither` items are not scored.

Stdlib only. Usage:
    python3 ml/adjudicated.py build --key K.json --verdicts V1.tsv V2.tsv ...
        --corpus ml/data/corpus.jsonl --crossval ml/data/crossval.jsonl -o OUT
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, "eval", "adjudicated-2026-10-22.jsonl")


def load(path=DEFAULT):
    with open(path, encoding="utf-8") as fh:
        return [json.loads(ln) for ln in fh if ln.strip()]


def acceptable(item):
    v = item["verdict"]
    if v == "engine":
        return [item["engine"]]
    if v == "model":
        return [item["model"]]
    if v == "both":
        return [item["engine"], item["model"]]
    return []


def score(items, predict):
    """predict(item) -> list of starts. Returns (right, scored)."""
    right = scored = 0
    for it in items:
        ok = acceptable(it)
        if not ok:
            continue
        scored += 1
        right += sorted(predict(it)) in [sorted(o) for o in ok]
    return right, scored


GOLD = os.path.join(HERE, "eval", "gold-2026-10-22.jsonl")
# 150 random lines labelled after every model decision was made; scored once.
TEST = os.path.join(HERE, "eval", "test-2026-10-22.jsonl")


def gold_sheet(a):
    """A labelling sheet: the 150 adjudicated lines plus N random labelled
    lines, each with numbered field-start candidates; reviewers answer with
    the numbers that start a field."""
    import random
    sys.path.insert(0, HERE)
    from layout import candidates
    corpus = {}
    for ln in open(a.corpus, encoding="utf-8"):
        e = json.loads(ln)
        corpus[e["name"]] = e
    items = [] if a.only_random else [(it["name"], it["line"], "disagree")
                                      for it in load(a.adjudicated)]
    taken = {(n, j) for n, j, _ in items} | {(it["name"], it["line"]) for it in load(a.adjudicated)}
    for path in a.exclude:
        taken |= {(g["name"], g["line"]) for g in load(path)}
    pool = [(n, j) for n, e in sorted(corpus.items()) for j, st in enumerate(e["starts"])
            if st and (n, j) not in taken]
    rng = random.Random(a.seed)
    items += [(n, j, "random") for n, j in rng.sample(pool, a.random)]
    rng.shuffle(items)
    meta = []
    with open(a.sheet_out, "w", encoding="utf-8") as fh:
        for k, (n, j, src) in enumerate(items, 1):
            e = corpus[n]
            line = e["lines"][j]
            cands = candidates(line)
            meta.append({"item": k, "name": n, "line": j, "text": line, "source": src,
                         "candidates": cands})
            lo, hi = max(0, j - 5), min(len(e["lines"]), j + 4)
            fh.write(f"### item {k}\ncontext:\n")
            for q in range(lo, hi):
                fh.write(("  >> " if q == j else "     ") + "|" + e["lines"][q] + "\n")
            parts = []
            for c, s0 in enumerate(cands):
                e0 = cands[c + 1] if c + 1 < len(cands) else len(line)
                parts.append(f"[{c + 1}] {line[s0:e0].rstrip()}")
            fh.write("candidates: " + "   ".join(parts) + "\n\n")
    with open(a.meta_out, "w", encoding="utf-8") as fh:
        json.dump(meta, fh)
    print(f"{len(items)} items -> {a.sheet_out}", file=sys.stderr)


def gold_ingest(a):
    meta = {m["item"]: m for m in json.load(open(a.meta, encoding="utf-8"))}
    out, bad = [], []
    for path in a.answers:
        for ln in open(path, encoding="utf-8"):
            p = ln.rstrip("\n").split("\t")
            if not p or not p[0].strip().isdigit():
                continue
            m = meta[int(p[0])]
            def starts(field):
                nums = [int(x) for x in field.replace(",", " ").split() if x.isdigit()]
                if not nums or any(x < 1 or x > len(m["candidates"]) for x in nums):
                    return None
                return sorted(m["candidates"][x - 1] for x in set(nums))
            st = starts(p[1]) if len(p) > 1 else None
            alt = starts(p[2]) if len(p) > 2 and p[2].strip() not in ("", "-") else None
            if st is None:
                bad.append(int(p[0]))
                continue
            out.append({"name": m["name"], "line": m["line"], "text": m["text"],
                        "source": m["source"], "starts": st, "alt": alt,
                        "note": p[3].strip() if len(p) > 3 else ""})
    with open(a.out, "w", encoding="utf-8") as fh:
        for r in sorted(out, key=lambda r: (r["name"], r["line"])):
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{len(out)} gold lines -> {a.out}; unusable answers: {sorted(bad)}", file=sys.stderr)


def canon(text, starts):
    """A field that starts at an opening bracket or quote starts at the value
    inside it: `[ 0.04]` and `"POST /"` are the same split either way, and
    the labellers chose the inside convention."""
    out = set()
    for s0 in starts or []:
        k = s0
        while k < len(text) and text[k] in "[(\"'{<" :
            k += 1
        while k < len(text) and text[k] == " ":
            k += 1
        out.add(k if k < len(text) else s0)
    return sorted(out)


def gold_score(items, predict):
    """Exact-split accuracy against the hand labels (either answer counts)."""
    right = 0
    for it in items:
        t = it["text"]
        p = canon(t, predict(it))
        right += p == canon(t, it["starts"]) or (it["alt"] is not None and p == canon(t, it["alt"]))
    return right, len(items)


def build(a):
    key = json.load(open(a.key, encoding="utf-8"))["items"]
    verdicts = {}
    for path in a.verdicts:
        for ln in open(path, encoding="utf-8"):
            p = ln.rstrip("\n").split("\t")
            if len(p) >= 2 and p[0].strip().isdigit():
                verdicts[int(p[0])] = (p[1].strip().lower(), p[2].strip() if len(p) > 2 else "")
    corpus = {}
    for ln in open(a.corpus, encoding="utf-8"):
        e = json.loads(ln)
        corpus[e["name"]] = e
    preds = {}
    for ln in open(a.crossval, encoding="utf-8"):
        e = json.loads(ln)
        preds[e["name"]] = e["starts"]
    sheet = open(a.sheet, encoding="utf-8").read().split("### item ")[1:]
    out = []
    for it in key:
        n = it["item"]
        block = sheet[n - 1]
        target = next(l for l in block.split("\n") if l.startswith("  >> |"))[len("  >> |"):]
        e = corpus[it["name"]]
        j = next(k for k, l in enumerate(e["lines"]) if l == target and e["starts"][k])
        v, why = verdicts[n]
        if v in ("a", "b"):
            v = it["A"] if v == "a" else ("engine" if it["A"] == "model" else "model")
        out.append({"item": n, "name": it["name"], "strategy": it["strategy"], "line": j,
                    "text": target, "engine": e["starts"][j], "model": preds[it["name"]][j],
                    "verdict": v, "reason": why})
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as fh:
        for r in out:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"wrote {len(out)} adjudicated lines to {a.out}", file=sys.stderr)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--key", required=True)
    b.add_argument("--sheet", required=True)
    b.add_argument("--verdicts", nargs="+", required=True)
    b.add_argument("--corpus", required=True)
    b.add_argument("--crossval", required=True)
    b.add_argument("-o", "--out", default=DEFAULT)
    g = sub.add_parser("gold-sheet")
    g.add_argument("--corpus", required=True)
    g.add_argument("--adjudicated", default=DEFAULT)
    g.add_argument("--random", type=int, default=150)
    g.add_argument("--seed", type=int, default=7)
    g.add_argument("--only-random", action="store_true", help="random lines only (a fresh test set)")
    g.add_argument("--exclude", nargs="*", default=[], help="labelled sets whose lines must not be drawn")
    g.add_argument("--sheet-out", required=True)
    g.add_argument("--meta-out", required=True)
    i = sub.add_parser("gold-ingest")
    i.add_argument("--meta", required=True)
    i.add_argument("--answers", nargs="+", required=True)
    i.add_argument("-o", "--out", default=GOLD)
    a = ap.parse_args(argv)
    {"build": build, "gold-sheet": gold_sheet, "gold-ingest": gold_ingest}[a.cmd](a)


if __name__ == "__main__":
    main()
