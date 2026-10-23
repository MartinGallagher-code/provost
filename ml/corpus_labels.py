#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Derive layout-model labels from the tidy corpus.

For each tests/corpus/inputs/<tool>.txt with a frozen golden
tests/corpus/expected/<tool>.tsv, line the golden's cells back up with the raw
lines: a line holding a whole record is a `row`, one holding a key and its
value is `kv`, the line naming the columns is the `header`, and so on (roles
in layout.py). Where every value on a line is found in order at a field-start
candidate, the line's field starts are recorded too.

The goldens are what provost's generic parsers produce today, not hand labels,
so they carry its mistakes. Two filters keep the worst of that out:
  * strategies whose output does not live on the input lines (grammar
    formats, trees, the text-lines catch-all) are skipped outright;
  * a file is kept only when >= MIN_MATCH of its records line up.

Stdlib only. Usage:
    python3 ml/corpus_labels.py [--meta DIR] [-o ml/data/corpus.jsonl]
--meta is a directory of <tool>.meta files from
`provost-extract --batch --batch-out DIR --generic`; without it the engine is
run here (a few minutes).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extract", "model"))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(ROOT, "tests", "corpus")

# Output that is not a layout of the input lines: grammar formats (exact
# parsers already handle them), derived structure (tree depth/parent columns),
# and the catch-alls that mean "no structure found".
SKIP_STRATEGIES = {
    "json", "json-array", "jsonl", "xml", "toml", "har", "ndjson",
    "tree-view", "indent-tree", "indented-hierarchy", "group-children",
    "kv-under-group", "text-lines", "vertical-line", "(none)", "",
}
from align import (  # noqa: E402,F401  (moved to extract/model/align.py)
    EMPTY, KV_COLS, MAX_LINES, MIN_MATCH, POSITIONAL, ROW_WINDOW, Labeller, find_name,
    find_span, find_tok, label_file, match_seq, read_golden)


def strategies_from_engine(names):
    out = tempfile.mkdtemp(prefix="provost-ml-meta.")
    engine = os.path.join(ROOT, "extract", "provost-extract")
    paths = [os.path.join(CORPUS, "inputs", n + ".txt") for n in names]
    jobs = max(1, os.cpu_count() or 1)
    env = dict(os.environ)
    env.pop("GIT_DIR", None)
    procs = []
    for k in range(jobs):
        chunk = "\n".join(paths[k::jobs]) + "\n"
        pr = subprocess.Popen(["bash", engine, "--batch", "--batch-out", out, "--generic",
                               "-f", "tsv", "--max-strategies", "1"],
                              stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, env=env, text=True)
        pr.stdin.write(chunk)
        pr.stdin.close()
        procs.append(pr)
    for pr in procs:
        pr.wait()
    return out


def strategy_of(meta_dir, name):
    try:
        with open(os.path.join(meta_dir, name + ".meta"), encoding="utf-8") as fh:
            for ln in fh:
                f = ln.rstrip("\n").split("\t")
                if f[0] == "__EXTRACT_META__" and len(f) > 1:
                    return f[1]
    except OSError:
        pass
    return "(none)"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--meta", help="dir of <tool>.meta from a --generic --batch run")
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "ml", "data", "corpus.jsonl"))
    a = ap.parse_args(argv)
    names = sorted(f[:-4] for f in os.listdir(os.path.join(CORPUS, "expected")) if f.endswith(".tsv"))
    meta = a.meta or strategies_from_engine(names)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    kept = dropped_strat = dropped_match = 0
    roles_seen = {}
    with open(a.out, "w", encoding="utf-8") as out:
        for name in names:
            strat = strategy_of(meta, name)
            if strat in SKIP_STRATEGIES:
                dropped_strat += 1
                continue
            with open(os.path.join(CORPUS, "inputs", name + ".txt"), encoding="utf-8",
                      errors="replace") as fh:
                text = fh.read()
            cols, rows = read_golden(os.path.join(CORPUS, "expected", name + ".tsv"))
            if not rows:
                dropped_match += 1
                continue
            lab, att, mat = label_file(text, cols, rows)
            if att == 0 or mat < MIN_MATCH * att:
                dropped_match += 1
                continue
            kept += 1
            for r in lab.roles:
                roles_seen[r] = roles_seen.get(r, 0) + 1
            out.write(json.dumps({"name": name, "source": "corpus", "strategy": strat,
                                  "lines": lab.lines, "roles": lab.roles,
                                  "starts": lab.starts}, ensure_ascii=False) + "\n")
    print(f"kept {kept} files; dropped {dropped_strat} (strategy not a line layout), "
          f"{dropped_match} (records did not line up)", file=sys.stderr)
    print("roles: " + ", ".join(f"{k}={v}" for k, v in sorted(roles_seen.items())), file=sys.stderr)


if __name__ == "__main__":
    main()
