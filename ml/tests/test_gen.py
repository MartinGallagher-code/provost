# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tests for the format generators (ml/gen/), stdlib only.

    python3 -m unittest discover -s ml/tests -v
"""
import os
import random
import sys
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.join(ROOT, "ml", "gen"))
sys.path.insert(0, os.path.join(ROOT, "ml", "llm"))
import check  # noqa: E402
import run  # noqa: E402
from lib import Doc  # noqa: E402


class DocBuilder(unittest.TestCase):
    def test_tables_and_records_label_themselves(self):
        d = Doc()
        d.table(["NAME", None, "SIZE"], [["web-1", "x", "10G"], ["db", None, "1G"]], right=(2,), rule="-")
        d.blank()
        d.kvs([("Status", "ok"), ("Long key", "two words")])
        d.pipe_table(["id", "name"], [["1", "a"], ["22", None]])
        roles, starts, problems = check.convert(d.label(), d.lines)
        self.assertEqual(problems, [])
        self.assertEqual(roles[:4], ["header", "skip", "row", "row"])
        self.assertEqual(starts[3], [0, d.lines[3].index("1G")])

    def test_every_generator_passes_the_checker(self):
        families = run.corpus_families()
        tools = os.path.join(ROOT, "ml", "gen", "tools")
        for f in sorted(os.listdir(tools)):
            if f.endswith(".py"):
                self.assertEqual(run.check_one(os.path.join(tools, f), families, n=3), [], f)


if __name__ == "__main__":
    unittest.main()
