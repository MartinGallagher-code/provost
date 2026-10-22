# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Stdlib-only tests for the layout-model training set (no numpy/torch).

    python3 -m unittest discover -s ml/tests -v
"""
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import corpus_labels as CL  # noqa: E402
import dataset as D  # noqa: E402
import synth  # noqa: E402
from features import NBASE, cand_rows, line_rows  # noqa: E402
from layout import PREDICTED, ROLES, candidates, fields  # noqa: E402


def label(text, cols, rows):
    lab, att, mat = CL.label_file(text, cols, rows)
    return lab.roles, lab.starts, att, mat


class Layout(unittest.TestCase):
    def test_candidates(self):
        self.assertEqual(candidates("ab  cd,ef|g"), [0, 4, 7, 10])
        self.assertEqual(candidates("  x"), [2])
        self.assertEqual(candidates(""), [])

    def test_fields(self):
        self.assertEqual(fields("| a | b c |", [2, 6]), ["a", "b c"])
        self.assertEqual(fields("k: v", [0, 3]), ["k:", "v"])


class CorpusLabels(unittest.TestCase):
    def test_aligned_table(self):
        text = ("Filesystem  Size  Mounted on\n"
                "/dev/sda1   100G  /\n"
                "tmpfs       7.9G  /dev/shm\n")
        roles, starts, att, mat = label(text, ["Filesystem", "Size", "Mounted_on"],
                                        [["/dev/sda1", "100G", "/"], ["tmpfs", "7.9G", "/dev/shm"]])
        self.assertEqual(roles, ["header", "row", "row"])
        self.assertEqual(starts, [[0, 12, 18], [0, 12, 18], [0, 12, 18]])
        self.assertEqual((att, mat), (2, 2))

    def test_positional_table_has_no_header(self):
        text = "rule\na b\nc d\n"
        roles, starts, _, _ = label(text, ["A", "B"], [["a", "b"], ["c", "d"]])
        self.assertEqual(roles, ["skip", "row", "row"])

    def test_wide_single_record_is_kv(self):
        text = "MemTotal:   8 kB\nMemFree:    3 kB\n\nEXPIRE=\n"
        roles, starts, _, mat = label(text, ["MemTotal", "MemFree", "EXPIRE"], [["8 kB", "3 kB", ""]])
        self.assertEqual(roles, ["kv", "kv", "blank", "kv"])
        self.assertEqual(starts[0], [0, 12])
        self.assertEqual(starts[3], [0])
        self.assertEqual(mat, 1)

    def test_key_value_golden_is_kv(self):
        text = "Total commands:  881\nUnique:  41\n"
        roles, starts, _, _ = label(text, ["key", "value"], [["Total commands", "881"], ["Unique", "41"]])
        self.assertEqual(roles, ["kv", "kv"])
        self.assertEqual(starts[0], [0, 17])

    def test_block_records(self):
        text = "Package: curl\nVersion: 7.8\n\nPackage: wget\nVersion: 1.2\n"
        roles, starts, _, mat = label(text, ["Package", "Version"], [["curl", "7.8"], ["wget", "1.2"]])
        self.assertEqual(roles, ["kv", "kv", "blank", "kv", "kv"])
        self.assertEqual(mat, 2)

    def test_section_column(self):
        text = "--- Shared Memory ---\nkey   owner\n0x1   root\n0x2   pg\n"
        roles, starts, _, _ = label(text, ["key", "owner", "title"],
                                    [["0x1", "root", "Shared Memory"], ["0x2", "pg", "Shared Memory"]])
        self.assertEqual(roles, ["section", "header", "row", "row"])
        self.assertEqual(starts[2], [0, 6])

    def test_whitespace_inside_value_matches_any_run(self):
        self.assertEqual(CL.find_span("x  +14us[  +18us] y", "+14us[ +18us]"), (3, 17))
        self.assertEqual(CL.find_tok("abc", "b"), -1)      # not a whole field

    def test_unmatched_file_reports_low_match(self):
        _, _, att, mat = label("nothing here\n", ["A"], [["zzz"]])
        self.assertEqual((att, mat), (1, 0))


class Synth(unittest.TestCase):
    def test_deterministic(self):
        a = synth.example(random.Random(7), 0)
        b = synth.example(random.Random(7), 0)
        self.assertEqual(a, b)

    def test_labels_are_consistent(self):
        rng = random.Random(3)
        styles = set()
        for k in range(400):
            ex = synth.example(rng, k)
            styles.add(ex["style"])
            self.assertEqual(len(ex["lines"]), len(ex["roles"]))
            self.assertEqual(len(ex["lines"]), len(ex["starts"]))
            for line, role, st in zip(ex["lines"], ex["roles"], ex["starts"]):
                self.assertIn(role, ROLES)
                self.assertEqual(role == "blank", not line.strip(), (ex["style"], line))
                if st:
                    self.assertEqual(st, sorted(st))
                    self.assertTrue(set(st) <= set(candidates(line)), (ex["style"], line, st))
        self.assertEqual(len(styles), len(synth.DOCS))


class Dataset(unittest.TestCase):
    def test_split_by_family(self):
        a = {"name": "docker-ps"}
        b = {"name": "docker_images"}
        self.assertEqual(D.is_test(a), D.is_test(b))
        self.assertEqual(D.family("Foo-bar_baz"), "foo")

    def test_rules(self):
        self.assertEqual(D.rule_ws("a b  c"), {0, 2, 5})
        self.assertEqual(D.rule_gap2("a b  c"), {0, 5})
        self.assertEqual(D.rule_gap2("a,b, c"), {0, 2, 5})

    def test_reports(self):
        r = D.bound_report([{0, 4}, {0}], [{0, 4}, {0, 2}])
        self.assertEqual(r["exact"], 0.5)
        rr = D.role_report([0, 1, 1], [0, 1, 0])
        self.assertAlmostEqual(rr["acc"], 2 / 3)


class Features(unittest.TestCase):
    def test_shapes(self):
        ex = synth.example(random.Random(11), 0)
        rows = line_rows(ex)
        nonblank = sum(1 for ln in ex["lines"] if ln.strip())
        self.assertEqual(len(rows), nonblank)
        self.assertTrue(all(len(f) == len(rows[0][0]) > NBASE for f, _, _ in rows))
        self.assertTrue(all(0 <= r < len(PREDICTED) for _, r, _ in rows))
        cr = cand_rows(ex)
        self.assertEqual(sum(lab for _, lab, _, _ in cr),
                         sum(len(st) for st in ex["starts"] if st))


if __name__ == "__main__":
    unittest.main()
