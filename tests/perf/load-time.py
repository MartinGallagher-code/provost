#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# load-time.py N [COLS] — how long provost_data.load / load_df take on a dataset
# of N rows (PV-031). Not part of any gate: a measurement.
#
# Files a capture of 100 rows x COLS columns (default 8; every tenth cell of
# the last column blank) into a fresh store, then extends the dataset's file to
# N rows of the same shape directly: filing is not what is timed, and provost
# takes minutes to file 100,000 rows. Then it times, best of 3:
#   show_tsv   `provost show NAME --tsv` alone (the subprocess load reads)
#   load       provost_data.load (that subprocess, plus splitting into dicts)
#   load_df    provost_data.load_df (load, plus a DataFrame; needs pandas)
#   file_read  load with the subprocess swapped for reading the dataset's file
#              directly: what a reader of the store's files (PV-022) would take
# and prints one line of seconds per measure. Runs this checkout's provost.
import os
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "src"))
os.environ["PATH"] = REPO + os.pathsep + os.environ.get("PATH", "")

import provost_data  # noqa: E402
from provost_data import _dataset  # noqa: E402


def best(fn, runs=3):
    times = []
    for _ in range(runs):
        t0 = time.perf_counter()
        fn()
        times.append(time.perf_counter() - t0)
    return min(times)


def main():
    n = int(sys.argv[1])
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    with tempfile.TemporaryDirectory() as d:
        store = os.path.join(d, ".store")
        env = dict(os.environ, PROVOST_WORKSPACE=store, PROVOST_HOME=os.path.join(d, "home"),
                   PROVOST_ASYNC="0")
        def cells(i):
            row = ["h%06d" % i] + ["%d.%d" % (i, c) for c in range(1, cols)]
            if i % 10 == 0:
                row[-1] = ""
            return row

        sample = min(n, 100)
        lines = ["\t".join("c%d" % c for c in range(cols))]
        lines += ["\t".join(cells(i)) for i in range(sample)]
        subprocess.run([os.path.join(REPO, "provost"), "--name", "big"],
                       input=("\n".join(lines) + "\n").encode(), env=env, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        path = os.path.join(store, "datasets", "big.tsv")
        with open(path, "a", encoding="utf-8") as f:
            for i in range(sample, n):
                f.write("%d\tc0001\t%d\t%s\n" % (i + 1, i + 1, "\t".join(cells(i))))
        rows = len(provost_data.load("big", store=store))
        assert rows == n, (rows, n)
        out = {
            "show_tsv": best(lambda: subprocess.run(
                [os.path.join(REPO, "provost"), "show", "big", "--tsv"], env=env, check=True,
                stdout=subprocess.PIPE)),
            "load": best(lambda: provost_data.load("big", store=store)),
        }
        tsv = _dataset._tsv
        _dataset._tsv = lambda name, store, capture: open(path, encoding="utf-8").read()
        out["file_read"] = best(lambda: provost_data.load("big", store=store))
        _dataset._tsv = tsv
        try:
            import pandas  # noqa: F401
            out["load_df"] = best(lambda: provost_data.load_df("big", store=store))
        except ImportError:
            out["load_df"] = None
        size = os.path.getsize(path)
    print("N=%d cols=%d tsv=%.1fMB " % (n, cols, size / 1e6)
          + " ".join("%s=%s" % (k, "n/a" if v is None else "%.3fs" % v) for k, v in out.items()))


if __name__ == "__main__":
    main()
