# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Score LLM labels: against the hand labels, against the engine, and what a
run over the whole corpus would cost.

    python3 ml/llm/score.py LABELS [--names FILE] [--corpus ml/data/corpus.jsonl]
                            [--sheet OUT.md]

LABELS is a directory of <tool>.json labels (label.py writes ml/data/llm/) or
one .jsonl file of them (ml/eval/llm-pilot-*.jsonl). The
engine's split of a line comes from corpus.jsonl (corpus_labels.py) when the
tool is there, else from running the engine on the capture. --sheet writes
every line where the two disagree, side by side, for review. Stdlib only.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "ml"))
sys.path.insert(0, os.path.join(ROOT, "extract", "model"))
import adjudicated as ADJ  # noqa: E402
import check  # noqa: E402

INPUTS = os.path.join(ROOT, "tests", "corpus", "inputs")
EXPECTED = os.path.join(ROOT, "tests", "corpus", "expected")
GUIDE = os.path.join(HERE, "GUIDE.md")
# list prices per million tokens (input, output, cache read); batch is half
PRICES = {"claude-opus-5-5": (4.0, 20.0, 0.20), "claude-sonnet-5-5": (2.0, 10.0, 0.20)}


def engine_starts(name, lines):
    from layout_model import engine_starts as es
    out = subprocess.run(["bash", os.path.join(ROOT, "extract", "provost-extract"), "-f", "tsv",
                          os.path.join(INPUTS, f"{name}.txt")], capture_output=True, text=True,
                         env={**os.environ, "PROVOST_NO_RC": "1"}, timeout=120).stdout
    return es(lines, out)


def load_labels(path):
    """A directory of <tool>.json labels, or one .jsonl file of them."""
    if os.path.isdir(path):
        return {f[:-5]: json.load(open(os.path.join(path, f), encoding="utf-8"))
                for f in os.listdir(path) if f.endswith(".json")}
    out = {}
    for ln in open(path, encoding="utf-8"):
        d = json.loads(ln)
        out[d["name"]] = d
    return out


def split(text, st):
    st = st or []
    return " | ".join(text[a:b].rstrip() for a, b in zip(st, st[1:] + [len(text)]))


def tokens(chars):
    return chars / 3.5


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("labels")
    ap.add_argument("--names")
    ap.add_argument("--corpus", default=os.path.join(ROOT, "ml", "data", "corpus.jsonl"))
    ap.add_argument("--sheet")
    a = ap.parse_args(argv)

    labels = load_labels(a.labels)
    names = open(a.names).read().split() if a.names else sorted(labels)
    corpus = {}
    if os.path.exists(a.corpus):
        for ln in open(a.corpus, encoding="utf-8"):
            e = json.loads(ln)
            corpus[e["name"]] = e
    llm, eng, held, bad = {}, {}, set(), []
    for n in names:
        lines = check.read_lines(os.path.join(INPUTS, f"{n}.txt"))
        label = labels[n]
        roles, starts, problems = check.convert(label, lines)
        if problems:
            bad.append(n)
        llm[n] = (lines, roles, starts)
        if not os.path.exists(os.path.join(EXPECTED, f"{n}.tsv")):
            held.add(n)
        if n in corpus and corpus[n]["lines"] == lines:
            eng[n] = (corpus[n]["roles"], corpus[n]["starts"])
        else:
            eng[n] = (None, engine_starts(n, lines))

    print(f"{len(names)} captures labelled, {len(bad)} failing the checker {bad or ''}")
    print(f"  {len(names) - len(held)} the engine files today, {len(held)} it holds back")

    # 1. the hand labels
    for title, path in (("hand-labelled lines (gold)", ADJ.GOLD), ("fresh test lines", ADJ.TEST)):
        items = [g for g in ADJ.load(path) if g["name"] in llm]
        if not items:
            continue
        def lp(g):
            return check.snap(g["text"], llm[g["name"]][2][g["line"]])
        r, k = ADJ.gold_score(items, lp)
        re_, _ = ADJ.gold_score(items, lambda g: (eng[g["name"]][1] or [None] * 9999)[g["line"]])
        print(f"\n{title} in these captures: LLM {r}/{k}   engine {re_}/{k}")
        for g in items:
            t = g["text"]
            ok_l = ADJ.gold_score([g], lp)[0]
            if not ok_l:
                print(f"    LLM miss  {g['name']}:{g['line']}  hand: {split(t, g['starts'])}")
                print(f"              {'':{len(g['name']) + len(str(g['line'])) + 1}}  LLM:  "
                      f"{split(t, llm[g['name']][2][g['line']])}")

    # 2. agreement with the engine
    agree = tot = files_all = roles_ok = roles_n = 0
    rows = []
    for n in names:
        if n in held:
            continue
        lines, lroles, lst = llm[n]
        eroles, est = eng[n]
        all_ok = True
        for j, t in enumerate(lines):
            if not t.strip():
                continue
            if eroles is not None:
                roles_n += 1
                roles_ok += eroles[j] == lroles[j]
            e, m = est[j] if est else None, check.snap(t, lst[j]) if lst[j] else None
            if not e and not m:
                continue
            # corpus.jsonl keeps no split for section titles (and some
            # headers): those lines are compared by role above, not here
            if eroles is not None and not e and eroles[j] in ("section", "header") \
                    and eroles[j] == lroles[j]:
                continue
            tot += 1
            same = bool(e) and bool(m) and ADJ.canon(t, e) == ADJ.canon(t, m)
            agree += same
            if not same:
                all_ok = False
                rows.append((n, j, t, split(t, e), split(t, m)))
        files_all += all_ok
    covered = len(names) - len(held)
    print(f"\nagreement with the engine on the {covered} filed captures:")
    print(f"  line splits:  {agree}/{tot} = {agree / max(1, tot):.3f} agree "
          f"({tot - agree} lines differ)")
    if roles_n:
        print(f"  line roles:   {roles_ok}/{roles_n} = {roles_ok / roles_n:.3f} agree "
              f"(captures in corpus.jsonl only)")
    print(f"  captures where every line agrees: {files_all}/{covered}")

    hl = sum(len([t for t in llm[n][0] if t.strip()]) for n in held)
    hs = sum(1 for n in held for s in llm[n][2] if s)
    print(f"\nheld-back captures: the LLM labelled {hs} of their {hl} non-blank lines as data "
          f"({len(held)} captures provost files nothing for today)")

    # 3. cost of the whole corpus, from this sample's sizes
    guide = len(open(GUIDE, encoding="utf-8").read())
    sin = sum(len("\n".join(llm[n][0])) + 12 * len(llm[n][0]) for n in names)
    sout = sum(len(json.dumps(labels[n], ensure_ascii=False)) for n in names)
    all_in = sum(os.path.getsize(os.path.join(INPUTS, f)) for f in os.listdir(INPUTS)
                 if f.endswith(".txt"))
    k = len([f for f in os.listdir(INPUTS) if f.endswith(".txt")])
    scale = all_in / max(1, sum(os.path.getsize(os.path.join(INPUTS, f"{n}.txt")) for n in names))
    out_t = tokens(sout) * scale
    print(f"\nwhole corpus ({k} captures, scaled from this sample by input size x{scale:.0f}):")
    print(f"  input  ~{tokens(sin) * scale / 1e6:.2f}M tokens of capture + "
          f"{tokens(guide) * k / 1e6:.1f}M of guide (cached after the first request)")
    print(f"  output ~{out_t / 1e6:.2f}M tokens of labels, plus thinking")
    for model, (pi, po, pc) in PRICES.items():
        for think in (1, 3):
            usd = (tokens(sin) * scale * pi + tokens(guide) * k * pc + out_t * (1 + think) * po) / 1e6
            print(f"  {model:18} thinking {think}x the label: ~${usd:,.0f} "
                  f"(batch ~${usd / 2:,.0f})")

    if a.sheet:
        with open(a.sheet, "w", encoding="utf-8") as fh:
            fh.write("# Lines where the LLM and the engine split differently\n\n"
                     "For each line, mark which is right: `E` (engine), `L` (LLM), `both`, "
                     "or `neither` (and how it should split).\n\n")
            for i, (n, j, t, e, m) in enumerate(rows, 1):
                fh.write(f"### {i}. {n} line {j}\n\n    |{t}\n\n- E: {e or '(not data)'}\n"
                         f"- L: {m or '(not data)'}\n- verdict: \n\n")
        print(f"\n{len(rows)} disagreeing lines -> {a.sheet}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
