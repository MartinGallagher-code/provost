#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Label every input with the layout model and write its records (the
engine's flat record format, as layout_model.py prints them) to
OUTDIR/<stem>.rec, in one process so the tiny LM loads once.

    python3 tests/benchmark/model_records.py [--lm DIR] [--engine EDIR] OUTDIR INPUT...

--lm DIR labels with the tiny pretrained LM saved in DIR (ml/train_lm.py, or
an ml/export_lm.py export), else with the shipped trees. Without --engine
neither consults the arbiter, which needs the engine's own parse. With
--engine EDIR, EDIR/<stem>.wide (the engine's -f tsv output) and
EDIR/<stem>.meta (its --emit-meta line) are handed to the labeller's arbiter
as provost's --model hands over the parse the gate held (PV-012): the trees'
arbiter.json, or for the LM the one arbitrate.load_for_lm finds for DIR
(--arbiter FILE names one instead); the third column printed is how many
lines it switched to the engine's reading. When the whole input is not one table or one key/value
record, the report is cut into the model's own uniform sections, as
provost's --model does (layout_model.py --segments): <stem>.seg.N.txt (the
section's lines) and <stem>.seg.N.rec (its records, labelled in the context
of the whole input). An input the model reads nothing from, or one over the
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


def engine_meta(edir, stem):
    """The engine's strategy, confidence, coverage and consistency, tab
    separated, from its --emit-meta line ("" when there is none)."""
    try:
        with open(os.path.join(edir, stem + ".meta"), encoding="utf-8") as fh:
            for ln in fh:
                f = ln.rstrip("\n").split("\t")
                if f[0] == "__EXTRACT_META__":
                    return "\t".join(f[1:5])
    except OSError:
        pass
    return ""


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--lm", help="a tiny-LM model directory (else the trees)")
    ap.add_argument("--engine", help="dir of <stem>.wide / <stem>.meta: the engine's parse, to arbitrate with")
    ap.add_argument("--arbiter", help="with --engine: this arbiter file, not the one the model gets")
    ap.add_argument("outdir")
    ap.add_argument("inputs", nargs="+")
    a = ap.parse_args(argv)
    os.makedirs(a.outdir, exist_ok=True)
    import arbitrate
    if a.lm:
        import lm_runtime
        lm = lm_runtime.load_model(a.lm)     # fail loudly here: a benchmark must not fall back
        label = lambda lines: LMOD.label_lm(lm, lines, role_probs=True)  # noqa: E731
        coeffs = arbitrate.load(a.arbiter) if a.arbiter else arbitrate.load_for_lm(a.lm)
    else:
        trees = LMOD.load()
        label = lambda lines: (*LMOD.label(trees, lines), None)  # noqa: E731
        coeffs = arbitrate.load(a.arbiter or arbitrate.COEFFS)
    if a.engine and not coeffs:
        sys.exit(f"--engine: no arbiter for {a.lm or 'the trees'} (give one with --arbiter)")
    for path in a.inputs:
        stem = os.path.splitext(os.path.basename(path))[0]
        lines = read_lines(path)
        out, nseg, switched = [], 0, 0
        if lines and len(lines) <= LMOD.MAX_LINES:
            roles, starts, probs, rprobs = label(lines)
            wide = os.path.join(a.engine, stem + ".wide") if a.engine else ""
            if wide and os.path.isfile(wide):
                # the whole-input table only, as at capture time: the
                # model's own sections are cut from its unarbitrated labels
                env = {"PROVOST_LM_ENGINE_WIDE": wide, "PROVOST_LM_ENGINE_META": engine_meta(a.engine, stem)}
                ar = list(roles)
                st, switched = LMOD.arbitrate_with_engine(lines, ar, starts, probs, env, coeffs, rprobs)
                out = LMOD.records(lines, ar, st)
            else:
                out = LMOD.records(lines, roles, starts)
            if not out:
                for lo, hi, kind in LMOD.segments(lines, roles, starts):
                    rec = LMOD.segment_records(lines, roles, starts, lo, hi, kind)
                    if not rec:
                        continue
                    nseg += 1
                    base = os.path.join(a.outdir, f"{stem}.seg.{nseg}")
                    with open(base + ".txt", "w", encoding="utf-8") as fh:
                        fh.write("\n".join(lines[lo:hi + 1]) + "\n")
                    with open(base + ".rec", "w", encoding="utf-8") as fh:
                        fh.write("\n".join(rec) + "\n")
        with open(os.path.join(a.outdir, stem + ".rec"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(out) + ("\n" if out else ""))
        print(f"{stem}\t{len(out)}\t{nseg}\t{switched}", flush=True)


if __name__ == "__main__":
    main()
