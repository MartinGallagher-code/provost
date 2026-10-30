#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Label every input with the layout model and write its records (the
engine's flat record format, as layout_model.py prints them) to
OUTDIR/<stem>.rec, in one process so the tiny LM loads once.

    python3 tests/benchmark/model_records.py [--lm DIR] OUTDIR INPUT...

--lm DIR labels with the tiny pretrained LM saved in DIR (ml/train_lm.py),
else with the shipped trees. Neither consults the arbiter, which needs the
engine's own parse. An input the model reads nothing from, or one over the
runtime's line limit, gets an empty .rec. model_round.sh turns the records
into datasets.
"""
import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "extract", "model"))
import layout_model as LMOD  # noqa: E402


def read_lines(path):
    data = open(path, encoding="utf-8", errors="replace").read()
    lines = data.replace("\r\n", "\n").split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--lm", help="a tiny-LM model directory (else the trees)")
    ap.add_argument("outdir")
    ap.add_argument("inputs", nargs="+")
    a = ap.parse_args(argv)
    os.makedirs(a.outdir, exist_ok=True)
    if a.lm:
        import lm_runtime
        lm = lm_runtime.load_model(a.lm)     # fail loudly here: a benchmark must not fall back
        label = lambda lines: LMOD.label_lm(lm, lines)  # noqa: E731
    else:
        trees = LMOD.load()
        label = lambda lines: LMOD.label(trees, lines)  # noqa: E731
    for path in a.inputs:
        stem = os.path.splitext(os.path.basename(path))[0]
        lines = read_lines(path)
        out = []
        if lines and len(lines) <= LMOD.MAX_LINES:
            roles, starts, _ = label(lines)
            out = LMOD.records(lines, roles, starts)
        with open(os.path.join(a.outdir, stem + ".rec"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(out) + ("\n" if out else ""))
        print(f"{stem}\t{len(out)}", flush=True)


if __name__ == "__main__":
    main()
