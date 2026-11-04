# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""fold_eval.py keeps LightGBM and torch in separate processes (PV-014): on
macOS their two copies of libomp in one process crash it. Stdlib only, so
neither library is needed; the libraries' own imports are stood in for by
sys.modules entries.

    python3 -m unittest discover -s ml/tests -v
"""
import argparse
import os
import subprocess
import sys
import types
import unittest

ML = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, ML)
import fold_eval as FE  # noqa: E402

HEAVY = ("lightgbm", "torch", "numpy", "crossval", "train_baseline", "train_grid", "train_lm")


def args(learner, lm_trees=False):
    return argparse.Namespace(learner=learner, lm_trees=lm_trees)


def child_report(marker):
    """Runs in the child: its pid, and whether it can see marker (a module
    only the parent has) or any of the heavy modules."""
    return os.getpid(), marker in sys.modules, sorted(m for m in HEAVY if m in sys.modules)


class FoldEvalIsolation(unittest.TestCase):
    def test_learners(self):
        self.assertEqual(FE.learners(args("trees")), ["trees"])
        self.assertEqual(FE.learners(args("grid")), ["grid"])
        self.assertEqual(FE.learners(args("both")), ["trees", "grid"])
        self.assertEqual(FE.learners(args("lm")), ["lm"])
        self.assertEqual(FE.learners(args("lm", lm_trees=True)), ["trees", "lm"])
        self.assertEqual(FE.learners(args("grid", lm_trees=True)), ["grid"])

    def test_plan_splits_only_mixed_runs(self):
        # The trees stay here and every torch learner goes to a child, but only
        # when both kinds are in the run: a one-library run stays in one process.
        self.assertEqual(FE.plan(["trees", "grid"]), [("trees", False), ("grid", True)])
        self.assertEqual(FE.plan(["trees", "lm"]), [("trees", False), ("lm", True)])
        self.assertEqual(FE.plan(["trees"]), [("trees", False)])
        self.assertEqual(FE.plan(["grid"]), [("grid", False)])
        self.assertEqual(FE.plan(["lm"]), [("lm", False)])
        for ks in (["trees", "grid"], ["trees", "lm"]):
            with self.subTest(ks=ks):
                here = {k for k, child in FE.plan(ks) if not child}
                there = {k for k, child in FE.plan(ks) if child}
                self.assertFalse(here & set(FE.TORCH), "torch would load beside LightGBM")
                self.assertFalse(there - set(FE.TORCH), "LightGBM would load in the torch child")

    def test_import_loads_neither_library(self):
        # The child process re-imports fold_eval, so this is what it starts
        # with: if importing it pulled in LightGBM, the torch child would have
        # both libomps again.
        code = (f"import sys; sys.path.insert(0, {ML!r}); import fold_eval; "
                f"print(sorted(m for m in {HEAVY!r} if m in sys.modules))")
        out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True)
        self.assertEqual(out.stdout.strip(), "[]")

    def test_child_is_a_fresh_process(self):
        # A module loaded here (as LightGBM is, once the trees have trained)
        # must not be in the child: spawn, not fork.
        marker = "pv014_parent_only_module"
        sys.modules[marker] = types.ModuleType(marker)
        try:
            pid, seen, heavy = FE.in_child(child_report, marker)
        finally:
            del sys.modules[marker]
        self.assertNotEqual(pid, os.getpid())
        self.assertFalse(seen)
        self.assertEqual(heavy, [])

    def test_run_learners_routes_torch_to_a_child(self):
        # run_learners with predict and in_child stood in for: the trees run
        # here, the torch learner through in_child, and the results come back
        # under each learner's name.
        calls = []
        real = FE.predict, FE.in_child
        FE.predict = lambda k, a, *data: calls.append(("here", k)) or {"doc": k}
        FE.in_child = lambda fn, k, a: calls.append(("child", k)) or {"doc": k}
        try:
            for learner, lm_trees, want in (
                    ("both", False, [("here", "trees"), ("child", "grid")]),
                    ("lm", True, [("here", "trees"), ("child", "lm")]),
                    ("grid", False, [("here", "grid")]),
                    ("trees", False, [("here", "trees")])):
                with self.subTest(learner=learner, lm_trees=lm_trees):
                    calls.clear()
                    preds = FE.run_learners(args(learner, lm_trees), ({}, [], []))
                    self.assertEqual(calls, want)
                    self.assertEqual(preds, {k: {"doc": k} for _, k in want})
        finally:
            FE.predict, FE.in_child = real


if __name__ == "__main__":
    unittest.main()
