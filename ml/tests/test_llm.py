# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tests for the LLM-label checker (ml/llm/check.py), stdlib only.

    python3 -m unittest discover -s ml/tests -v
"""
import json
import os
import sys
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.join(ROOT, "ml", "llm"))
import check  # noqa: E402

LINES = ["NAME   STATUS  AGE", "web-1  Running 5d", "db-1           2d", ""]


def label(*entries):
    return {"name": "t", "lines": [{"n": j, "role": r, "cells": c} for j, (r, c) in enumerate(entries)]}


class Convert(unittest.TestCase):
    def test_a_good_label_gives_roles_and_starts(self):
        lab = label(("header", ["NAME", "STATUS", "AGE"]), ("row", ["web-1", "Running", "5d"]),
                    ("row", ["db-1", None, "2d"]), ("blank", []))
        roles, starts, problems = check.convert(lab, LINES)
        self.assertEqual(problems, [])
        self.assertEqual(roles, ["header", "row", "row", "blank"])
        self.assertEqual(starts, [[0, 7, 15], [0, 7, 15], [0, 15], None])

    def test_problems_are_reported(self):
        lab = label(("header", ["NAME", "STATUS", "AGE"]), ("row", ["Running", "web-1", "5d"]),
                    ("row", ["db-1", "2d"]), ("skip", ["x"]))
        problems = check.convert(lab, LINES)[2]
        self.assertTrue(any("out of order" in p for p in problems))
        self.assertTrue(any("row has 2 cells but the header above has 3" in p for p in problems))
        self.assertTrue(any("takes no cells" in p for p in problems))

    def test_missing_lines_are_reported(self):
        self.assertIn("once each", check.convert(label(("row", ["a"])), LINES)[2][0])

    def test_snap_moves_starts_to_candidates(self):
        # the model can't start a field after a tree glyph: it starts at the glyph
        self.assertEqual(check.snap("├─sda1  8:1", [2, 8]), [0, 8])


class ToCorpus(unittest.TestCase):
    def test_a_pilot_label_becomes_a_training_example(self):
        import to_corpus
        path = os.path.join(ROOT, "ml", "eval", "llm-pilot-2026-10-23.jsonl")
        labs = {json.loads(ln)["name"]: json.loads(ln) for ln in open(path, encoding="utf-8")}
        ex = to_corpus.example("git-ls-tree", labs["git-ls-tree"])
        self.assertEqual(ex["strategy"], "llm")
        self.assertEqual(len(ex["lines"]), len(ex["roles"]))
        self.assertEqual(ex["starts"][0], [0, 7, 12, 53])


class Files(unittest.TestCase):
    def test_numbered_and_raw_inputs_read_the_same(self):
        with tempfile.TemporaryDirectory() as d:
            raw, num = os.path.join(d, "raw.txt"), os.path.join(d, "num.txt")
            with open(raw, "w", encoding="utf-8") as fh:
                fh.write("\n".join(LINES) + "\n")
            with open(num, "w", encoding="utf-8") as fh:
                fh.write("".join(f"{j} |{t}\n" for j, t in enumerate(LINES)))
            self.assertEqual(check.read_lines(raw), LINES)
            self.assertEqual(check.read_lines(num), LINES)

    def test_the_committed_pilot_labels_pass(self):
        path = os.path.join(ROOT, "ml", "eval", "llm-pilot-2026-10-23.jsonl")
        for ln in open(path, encoding="utf-8"):
            lab = json.loads(ln)
            lines = check.read_lines(os.path.join(ROOT, "tests", "corpus", "inputs",
                                                  f"{lab['name']}.txt"))
            self.assertEqual(check.convert(lab, lines)[2], [], lab["name"])


if __name__ == "__main__":
    unittest.main()
