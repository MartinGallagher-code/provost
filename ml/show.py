#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Print labelled examples for eyeballing: role, then the line with field
starts marked by a caret line underneath.

    python3 ml/show.py ml/data/corpus.jsonl [name ...]   # named, or 5 random
"""
import json
import random
import sys


def show(ex, out=sys.stdout):
    tag = ex.get("strategy") or ex.get("style") or ""
    out.write(f"=== {ex['name']} [{ex['source']} {tag}]\n")
    for line, role, st in zip(ex["lines"], ex["roles"], ex["starts"]):
        out.write(f"{role:8} |{line}\n")
        if st:
            marks = [" "] * (max(st) + 1)
            for s in st:
                marks[s] = "^"
            out.write(f"{'':8} |{''.join(marks)}\n")


def main(argv):
    exs = [json.loads(ln) for ln in open(argv[0], encoding="utf-8")]
    if len(argv) > 1:
        want = set(argv[1:])
        pick = [e for e in exs if e["name"] in want]
    else:
        pick = random.sample(exs, min(5, len(exs)))
    for e in pick:
        show(e)


if __name__ == "__main__":
    main(sys.argv[1:])
