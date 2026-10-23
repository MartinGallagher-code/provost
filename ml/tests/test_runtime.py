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
import align  # noqa: E402
import arbitrate  # noqa: E402
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


MIXED = ["Cluster:      orders-db", "Namespace:    shop-prod", "Status:       Cluster in healthy state",
         "Instances:    3", "Pod            Role       Status     Lag (bytes)   Timeline",
         "orders-db-1    primary    running    0             2",
         "orders-db-2    replica    streaming  12048         2",
         "orders-db-3    replica    streaming  8812          2"]


class Segments(unittest.TestCase):
    def test_a_mixed_report_splits_into_a_record_and_a_table(self):
        roles, starts, _ = LM.label(LM.load(), MIXED)
        segs = LM.segments(MIXED, roles, starts)
        self.assertEqual([(a, b, k) for a, b, k in segs], [(0, 3, "kv"), (4, 7, "table")])
        kv = LM.segment_records(MIXED, roles, starts, 0, 3, "kv")
        self.assertIn("Status Cluster in healthy state", kv)
        tab = LM.segment_records(MIXED, roles, starts, 4, 7, "table")
        self.assertIn("entry2.Lag_(bytes) 12048", tab)

    def test_hysteresis_keeps_a_table_whole(self):
        # rows alternate between two and three fields: still one table run
        roles = ["row"] * 4
        starts = [[0, 4, 9], [0, 4], [0, 4, 9], [0, 4, 9]]
        self.assertEqual(LM._kinds(roles, starts), ["table"] * 4)


class Arbiter(unittest.TestCase):
    def test_rows_from_wide(self):
        wide = "entry1.A\tentry1.B\tentry2.A\tentry2.B\ttotal_entries\nx\t1\ty\t2\t2\n"
        self.assertEqual(align.rows_from_wide(wide), (["A", "B"], [["x", "1"], ["y", "2"]]))

    def test_engine_starts_line_up(self):
        lines = ["web   up", "db    down"]
        st = LM.engine_starts(lines, "entry1.A\tentry1.B\tentry2.A\tentry2.B\nweb\tup\tdb\tdown\n")
        self.assertEqual(st, [[0, 6], [0, 6]])

    def test_choose_keeps_agreeing_lines(self):
        model = {"coef": [0.0] * 13, "intercept": 5.0}       # always prefers the engine
        out, n = arbitrate.choose(model, ["row", "row"], [[0, 6], [0, 6]], [[0, 6], [0, 3, 6]],
                                  [{0: .9, 6: .9}, {0: .9, 3: .6, 6: .9}], [60, 70, -1], "aligned-columns")
        self.assertEqual((out, n), ([[0, 6], [0, 6]], 1))

    def test_shipped_coefficients_load(self):
        m = arbitrate.load()
        self.assertEqual(len(m["coef"]), 13)


if __name__ == "__main__":
    unittest.main()
