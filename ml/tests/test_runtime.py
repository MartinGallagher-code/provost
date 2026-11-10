# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tests for the capture-time layout model (extract/model/), stdlib only.

    python3 -m unittest discover -s ml/tests -v
"""
import io
import json
import os
import sys
import tempfile
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


class LMArbiter(unittest.TestCase):
    """The tiny LM's own arbiter (PV-012): which coefficients apply to which
    model, the switch threshold, and the capture-time wiring."""
    ALWAYS_ENGINE = {"coef": [0.0] * 13, "intercept": 5.0}

    def model_dir(self, d, payload=b"weights"):
        with open(os.path.join(d, "config.json"), "w", encoding="utf-8") as fh:
            json.dump({"format": "provost-lm-numpy/1", "shards": ["weights-1.npz"]}, fh)
        with open(os.path.join(d, "weights-1.npz"), "wb") as fh:
            fh.write(payload)
        return d

    def write(self, path, obj):
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(obj, fh)
        return path

    def test_threshold_decides_the_switch(self):
        m = {"coef": [0.0] * 13, "intercept": 1.0}           # p(engine) = 0.73
        self.assertTrue(arbitrate.prefer_engine(m, [0.0] * 13))
        self.assertFalse(arbitrate.prefer_engine(dict(m, threshold=0.8), [0.0] * 13))
        self.assertAlmostEqual(arbitrate.p_engine(m, [0.0] * 13), 0.7311, places=4)

    def test_fingerprint_follows_the_weights(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            self.model_dir(a)
            self.model_dir(b)
            self.assertEqual(arbitrate.fingerprint(a), arbitrate.fingerprint(b))
            self.model_dir(b, b"weightz")                     # retrained: same shapes, other values
            self.assertNotEqual(arbitrate.fingerprint(a), arbitrate.fingerprint(b))
            self.assertRegex(arbitrate.fingerprint(a), "^[0-9a-f]{16}$")

    def test_the_models_own_arbiter_wins(self):
        with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as t:
            self.model_dir(d)
            own = dict(self.ALWAYS_ENGINE, threshold=0.7)
            self.write(os.path.join(d, "arbiter.json"), own)
            other = self.write(os.path.join(t, "lm.json"), dict(self.ALWAYS_ENGINE, model="0" * 16))
            self.assertEqual(arbitrate.load_for_lm(d, other), own)

    def test_provosts_arbiter_applies_to_its_model_only(self):
        with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as t:
            self.model_dir(d)
            fitted = dict(self.ALWAYS_ENGINE, model=arbitrate.fingerprint(d))
            path = self.write(os.path.join(t, "lm.json"), fitted)
            self.assertEqual(arbitrate.load_for_lm(d, path), fitted)
            self.model_dir(d, b"another model")
            self.assertIsNone(arbitrate.load_for_lm(d, path))
            self.write(path, self.ALWAYS_ENGINE)              # names no model: never applies
            self.assertIsNone(arbitrate.load_for_lm(d, path))

    def test_no_model_or_a_broken_file_means_no_arbiter(self):
        self.assertIsNone(arbitrate.load_for_lm(""))
        with tempfile.TemporaryDirectory() as d:
            self.model_dir(d)
            with open(os.path.join(d, "arbiter.json"), "w", encoding="utf-8") as fh:
                fh.write("{not json")
            self.assertIsNone(arbitrate.load_for_lm(d))
        self.assertIsNone(arbitrate.load_for_lm("/nonexistent/model"))

    def test_shipped_lm_arbiter_names_its_model(self):
        m = arbitrate.load(arbitrate.LM_COEFFS)
        self.assertEqual(len(m["coef"]), 13)
        self.assertRegex(m["model"], "^[0-9a-f]{16}$")
        self.assertTrue(0.5 <= m["threshold"] < 1)
        self.assertTrue(m["for"].startswith("provost-model "))

    def test_lm_dir(self):
        self.assertEqual(LM.lm_dir({"PROVOST_LAYOUT_LM": "0"}), "")
        self.assertEqual(LM.lm_dir({"PROVOST_LAYOUT_LM": "/some/model"}), "/some/model")

    def test_no_coefficients_leaves_the_split(self):
        with tempfile.TemporaryDirectory() as t:
            wide = os.path.join(t, "wide.tsv")
            with open(wide, "w", encoding="utf-8") as fh:
                fh.write("entry1.A\tentry1.B\tentry2.A\tentry2.B\nweb\tup\tdb\tdown\n")
            env = {"PROVOST_LM_ENGINE_WIDE": wide, "PROVOST_LM_ENGINE_META": "aligned-columns\t60\t100\t100"}
            lines, roles = ["web   up", "db    down"], ["row", "row"]
            starts = [[0, 3, 6], [0, 6]]
            probs = [{0: .9, 3: .6, 6: .9}, {0: .9, 6: .9}]
            self.assertEqual(LM.arbitrate_with_engine(lines, roles, starts, probs, env, coeffs=""), (starts, 0))
            self.assertEqual(LM.arbitrate_with_engine(lines, roles, starts, probs, env, coeffs=self.ALWAYS_ENGINE),
                             ([[0, 6], [0, 6]], 1))

    QHOST = ["HOSTNAME   ARCH      NCPU", "----------------------------",
             "global     -         -", "node01     lx-amd64  32", "node02     lx-amd64  64",
             "node03     lx-amd64  16"]

    def test_role_features_see_a_second_header(self):
        eng = ["header", "skip", "row", "row", "row", "row"]
        mod = ["header", "skip", "header", "row", "row", "row"]
        rp = [None, None, {"header": 0.8, "row": 0.1}, None, None, None]
        f = arbitrate.role_features(self.QHOST, eng, mod, rp, 2, [80, 100, 100], "vertical-line")
        self.assertEqual(len(f), 12)
        self.assertEqual(f[2:5], [1.0, 1.0, 0.0])          # the model's header, one above it, not first
        self.assertAlmostEqual(f[5], 2 / 3)                # "-" and "-" look like values, "global" not
        self.assertEqual(f[6:8], [2.0, 1.0])               # headers: the model's two, the engine's one
        self.assertTrue(arbitrate.role_contested(eng, mod, rp, 2))
        self.assertFalse(arbitrate.role_contested(eng, mod, rp, 0))
        self.assertFalse(arbitrate.role_contested(eng, mod, [None] * 6, 2))

    def test_choose_roles(self):
        eng = ["header", "skip", "row", "row", "row", "row"]
        mod = ["header", "skip", "header", "row", "row", "row"]
        rp = [None, None, {"header": 0.8, "row": 0.1}, None, None, None]
        with_roles = dict(self.ALWAYS_ENGINE, roles={"coef": [0.0] * 12, "intercept": 5.0})
        self.assertEqual(arbitrate.choose_roles(with_roles, self.QHOST, eng, mod, rp, [80, 100, 100], "x"),
                         (eng, 1))
        self.assertEqual(arbitrate.choose_roles(self.ALWAYS_ENGINE, self.QHOST, eng, mod, rp, [80, 100, 100], "x"),
                         (mod, 0))                       # no roles part: the model's roles stand

    def test_main_puts_a_data_line_back_under_the_header(self):
        """sge-qhost's case (round 4, 2026-10-30): the LM calls the `global`
        line a second header, which renames every column; the roles part
        keeps the engine's reading of it as a row."""
        lines = self.QHOST
        roles = ["header", "skip", "header", "row", "row", "row"]
        starts = [[0, 11, 21], None] + [[0, 11, 21]] * 4
        probs = [{0: .9, 11: .9, 21: .9}, None] + [{0: .9, 11: .9, 21: .9}] * 4
        rprobs = [{"header": 1.0}, {"skip": 1.0}, {"header": 0.83, "row": 0.02}] + [{"row": 1.0}] * 3
        saved = (LM.load_lm, LM.label_lm, dict(os.environ))
        try:
            LM.load_lm = lambda env=os.environ: ("model", "encoder")
            LM.label_lm = lambda lm, ls, role_probs=False: (list(roles), [None if x is None else list(x) for x in starts],
                                                            probs, rprobs)
            with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as t:
                self.model_dir(d)
                src = os.path.join(t, "in.txt")
                with open(src, "w", encoding="utf-8") as fh:
                    fh.write("\n".join(lines) + "\n")
                wide = os.path.join(t, "wide.tsv")
                with open(wide, "w", encoding="utf-8") as fh:
                    fh.write("entry1.HOSTNAME\tentry1.ARCH\tentry1.NCPU\tentry2.HOSTNAME\tentry2.ARCH\tentry2.NCPU\t"
                             "entry3.HOSTNAME\tentry3.ARCH\tentry3.NCPU\tentry4.HOSTNAME\tentry4.ARCH\tentry4.NCPU\n"
                             "global\t-\t-\tnode01\tlx-amd64\t32\tnode02\tlx-amd64\t64\tnode03\tlx-amd64\t16\n")
                os.environ.update(PROVOST_LAYOUT_LM=d, PROVOST_LM_ENGINE_WIDE=wide,
                                  PROVOST_LM_ENGINE_META="vertical-line\t80\t100\t100")
                self.write(os.path.join(d, "arbiter.json"),
                           {"coef": [0.0] * 13, "intercept": -5.0})        # splits: the model's
                rc, plain = run(src)
                self.assertEqual(rc, 0)
                self.assertIn("entry1.global node01\n", plain)
                self.write(os.path.join(d, "arbiter.json"),
                           {"coef": [0.0] * 13, "intercept": -5.0, "roles": {"coef": [0.0] * 12, "intercept": 5.0}})
                rc, fixed = run(src)
                self.assertEqual(rc, 0)
                self.assertIn("entry1.HOSTNAME global\n", fixed)
                self.assertIn("entry2.HOSTNAME node01\n", fixed)
        finally:
            LM.load_lm, LM.label_lm = saved[0], saved[1]
            os.environ.clear()
            os.environ.update(saved[2])

    def test_main_arbitrates_the_lms_labels(self):
        """layout_model.main with the LM labelling: the LM's arbiter (here one
        that always prefers the engine) keeps the engine's split where the
        two differ, and none is used when the LM has no arbiter: there the
        LM's own cut files the names as two columns."""
        lines = ["NAME    STATE", "web 1   up", "db 2    down", "mq 3    up"]
        lm_starts = [[0, 8], [0, 4, 8], [0, 3, 8], [0, 3, 8]]       # the LM cuts the names in two
        probs = [{0: .9, 8: .9}] + [{0: .9, k: .6, 8: .9} for k in (4, 3, 3)]
        saved = (LM.load_lm, LM.label_lm, dict(os.environ))
        try:
            LM.load_lm = lambda env=os.environ: ("model", "encoder")
            LM.label_lm = lambda lm, ls, role_probs=False: (["header", "row", "row", "row"],
                                                            [list(s) for s in lm_starts], probs, [None] * 4)
            with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as t:
                self.model_dir(d)
                src = os.path.join(t, "in.txt")
                with open(src, "w", encoding="utf-8") as fh:
                    fh.write("\n".join(lines) + "\n")
                wide = os.path.join(t, "wide.tsv")
                with open(wide, "w", encoding="utf-8") as fh:
                    fh.write("entry1.NAME\tentry1.STATE\tentry2.NAME\tentry2.STATE\tentry3.NAME\tentry3.STATE\n"
                         "web 1\tup\tdb 2\tdown\tmq 3\tup\n")
                os.environ.update(PROVOST_LAYOUT_LM=d, PROVOST_LM_ENGINE_WIDE=wide,
                                  PROVOST_LM_ENGINE_META="aligned-columns\t60\t100\t100")
                rc, plain = run(src)                    # no arbiter for this LM: its own cut
                self.assertEqual(rc, 0)
                self.assertIn("entry1.NAME web\nentry1.B 1\n", plain)
                self.write(os.path.join(d, "arbiter.json"), self.ALWAYS_ENGINE)
                rc, arbitrated = run(src)
                self.assertEqual(rc, 0)
                self.assertIn("entry1.NAME web 1\n", arbitrated)
                self.assertIn("entry2.STATE down\n", arbitrated)
        finally:
            LM.load_lm, LM.label_lm = saved[0], saved[1]
            os.environ.clear()
            os.environ.update(saved[2])


if __name__ == "__main__":
    unittest.main()
