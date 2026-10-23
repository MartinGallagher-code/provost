# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Turn LLM labels into a training set in corpus_labels.py's format, so the
trainers can learn from the LLM teacher instead of the engine.

    python3 ml/llm/to_corpus.py ml/data/llm [-o ml/data/corpus-llm.jsonl]

Each label becomes {name, source, strategy: "llm", lines, roles, starts}, with
starts snapped to the model's candidate offsets (check.snap). As in the
engine-derived set, only header / row / kv lines keep starts. Labels the
checker rejects are left out. Stdlib only.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import check  # noqa: E402
from score import load_labels  # noqa: E402

INPUTS = os.path.join(ROOT, "tests", "corpus", "inputs")
SPLIT_ROLES = ("header", "row", "kv")


def example(name, label):
    lines = check.read_lines(os.path.join(INPUTS, f"{name}.txt"))
    roles, starts, problems = check.convert(label, lines)
    if problems:
        return None
    out = []
    for t, r, s in zip(lines, roles, starts):
        out.append(check.snap(t, s) if s and r in SPLIT_ROLES else None)
    return {"name": name, "source": "llm", "strategy": "llm", "lines": lines,
            "roles": roles, "starts": out}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("labels", help="directory of <tool>.json labels, or a .jsonl of them")
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "ml", "data", "corpus-llm.jsonl"))
    a = ap.parse_args(argv)
    labels = load_labels(a.labels)
    kept = 0
    with open(a.out, "w", encoding="utf-8") as fh:
        for name in sorted(labels):
            if not os.path.exists(os.path.join(INPUTS, f"{name}.txt")):
                continue
            ex = example(name, labels[name])
            if ex:
                fh.write(json.dumps(ex, ensure_ascii=False) + "\n")
                kept += 1
    print(f"{kept}/{len(labels)} labels -> {a.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
