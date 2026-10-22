# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tests for the capture-time layout model (extract/model/), stdlib only.

    python3 -m unittest discover -s ml/tests -v
"""
import io
import os
import sys
import unittest
from contextlib import redirect_stdout

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.join(ROOT, "extract", "model"))
import features  # noqa: E402
import layout_model as LM  # noqa: E402

SAMPLE = os.path.join(ROOT, "extract", "samples", "layout-model", "basic.txt")
GOLDEN = os.path.join(ROOT, "extract", "tests", "golden", "layout-model.txt")


def run(path):
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = LM.main([path])
    return rc, buf.getvalue()


class Model(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = LM.load()

    def test_feature_vectors_match_the_model(self):
        cf = features.cand_features(["a b  c"], 0)
        lf = features.line_rows({"lines": ["a b"], "roles": ["row"], "starts": [None]})
        self.assertEqual(len(cf[0][1]), self.model["starts"]["num_features"])
        self.assertEqual(len(lf[0][0]), self.model["roles"]["num_features"])

    def test_sample_matches_the_strategy_golden(self):
        rc, out = run(SAMPLE)
        self.assertEqual(rc, 0)
        with open(GOLDEN, encoding="utf-8") as fh:
            want = [ln for ln in fh.read().splitlines() if ln.strip()]
        self.assertEqual([ln for ln in out.splitlines() if ln.strip()], want)

    def test_multi_word_values_stay_whole(self):
        _, out = run(SAMPLE)
        self.assertIn("entry1.LAST_SEEN 5 minutes ago", out)
        self.assertIn("entry1.PORTS 80/tcp, 443/tcp", out)


class Records(unittest.TestCase):
    def test_unnamed_first_column_is_positional(self):
        header = [(14, "total"), (26, "used")]
        row = [(0, "Mem:"), (15, "7982"), (27, "2341")]
        self.assertEqual(LM._align(row, header), [None, 0, 1])

    def test_equal_counts_zip(self):
        self.assertEqual(LM._align([(0, "a"), (5, "b")], [(0, "X"), (5, "Y")]), [0, 1])

    def test_merged_header_cell_is_split_where_rows_have_columns(self):
        line = "MS Name     Stratum Poll Reach"
        rows = [[(0, "^*"), (3, "ntp1"), (14, "2"), (19, "6"), (25, "377")]] * 3
        self.assertEqual(LM._resplit_header(line, [0, 3, 12], rows), [0, 3, 12, 20, 25])

    def test_a_mixed_report_is_declined(self):
        lines = ["Name: web", "Owner: ops", "", "ID  STATE", "1   up", "", "free text here", "more prose"]
        roles = ["kv", "kv", "blank", "header", "row", "blank", "skip", "skip"]
        starts = [[0, 6], [0, 7], None, [0, 4], [0, 4], None, None, None]
        self.assertEqual(LM.shape(lines, roles, starts), (None, set()))

    def test_key_value_record(self):
        lines = ["Name:   web", "Owner:  ops team", "Region: eu-west-1"]
        roles = ["kv"] * 3
        starts = [[0, 8], [0, 8], [0, 8]]
        self.assertEqual(LM.records(lines, roles, starts),
                         ["Name web", "Owner ops team", "Region eu-west-1"])

    def test_large_input_is_declined(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_big.txt")
        try:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("a b\n" * (LM.MAX_LINES + 1))
            self.assertEqual(run(path)[0], 3)
        finally:
            os.remove(path)


if __name__ == "__main__":
    unittest.main()
