# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Run the format generators in ml/gen/tools/ and write a training set.

    python3 ml/gen/run.py --check ml/gen/tools/zpool_iostat.py   # one generator: family new? 20 samples valid?
    python3 ml/gen/run.py -n 12 [-o ml/data/gen.jsonl]           # every generator, 12 samples each

Every sample is checked with ml/llm/check.py (cells verbatim, in order, rows
as wide as their header) and converted like the LLM labels
(ml/llm/to_corpus.py), so the trainers can mix it in. A generator whose tool
family is already in tests/corpus/ is refused: the corpus families are what
cross-validation and the hand-labelled sets are scored on. Stdlib only.
"""
import argparse
import importlib.util
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "ml"))
sys.path.insert(0, os.path.join(ROOT, "ml", "llm"))
sys.path.insert(1, os.path.join(ROOT, "extract", "model"))
import check  # noqa: E402
import dataset as D  # noqa: E402

TOOLS = os.path.join(HERE, "tools")
INPUTS = os.path.join(ROOT, "tests", "corpus", "inputs")
SPLIT_ROLES = ("header", "row", "kv")


def corpus_families():
    return {D.family(f[:-4]) for f in os.listdir(INPUTS) if f.endswith(".txt")}


def load(path):
    spec = importlib.util.spec_from_file_location("gen_" + os.path.basename(path)[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def sample(mod, seed):
    """-> (example, problems)."""
    doc = mod.generate(random.Random(seed))
    lines = list(doc.lines)
    roles, starts, problems = check.convert(doc.label(), lines)
    if problems:
        return None, problems
    out = [check.snap(t, s) if s and r in SPLIT_ROLES else None for t, r, s in zip(lines, roles, starts)]
    return {"name": f"gen-{mod.TOOL}-{seed}", "source": "gen", "strategy": "gen",
            "lines": lines, "roles": roles, "starts": out}, []


def check_one(path, families, n=20):
    mod = load(path)
    problems = []
    tool = getattr(mod, "TOOL", None)
    if not tool:
        return ["no TOOL defined"]
    if D.family(tool) in families:
        problems.append(f"tool family {D.family(tool)!r} is already in tests/corpus/: imitate a tool "
                        f"from a family the corpus doesn't have")
    for seed in range(n):
        try:
            ex, p = sample(mod, seed)
        except Exception as exc:  # a generator bug: report it like a label problem
            p = [f"generate() raised {type(exc).__name__}: {exc}"]
            ex = None
        if p:
            problems += [f"seed {seed}: {x}" for x in p[:3]]
            break
        if len([t for t in ex["lines"] if t.strip()]) < 2:
            problems.append(f"seed {seed}: fewer than 2 non-blank lines")
            break
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", nargs="+", help="check these generator files and stop")
    ap.add_argument("-n", type=int, default=12, help="samples per generator")
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "ml", "data", "gen.jsonl"))
    a = ap.parse_args(argv)
    families = corpus_families()
    if a.check:
        bad = 0
        for path in a.check:
            p = check_one(path, families)
            print(f"{path}: " + ("ok" if not p else "\n  " + "\n  ".join(p)))
            bad += bool(p)
        return 1 if bad else 0
    files = sorted(os.path.join(TOOLS, f) for f in os.listdir(TOOLS) if f.endswith(".py"))
    kept, skipped = 0, []
    seen = set()
    with open(a.out, "w", encoding="utf-8") as fh:
        for path in files:
            if check_one(path, families, n=3):
                skipped.append(os.path.basename(path))
                continue
            mod = load(path)
            if mod.TOOL in seen:
                skipped.append(os.path.basename(path) + " (duplicate TOOL)")
                continue
            seen.add(mod.TOOL)
            for seed in range(a.n):
                try:
                    ex, p = sample(mod, 1000 + seed)
                except Exception:
                    continue
                if ex:
                    fh.write(json.dumps(ex, ensure_ascii=False) + "\n")
                    kept += 1
    print(f"{len(files) - len(skipped)} generators, {kept} samples -> {a.out}", file=sys.stderr)
    if skipped:
        print("skipped: " + ", ".join(skipped), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
