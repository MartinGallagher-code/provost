# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""ml/arbiter.py and fold_eval.py --out (PV-012): which lines an arbiter is
fitted on, how its out-of-fold score counts lines and captures, and the
per-fold prediction files it reads. Stdlib, except the fits (numpy and
scikit-learn), which skip without them.

    python3 -m unittest discover -s ml/tests -v
"""
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(1, os.path.join(HERE, "..", "..", "extract", "model"))
import arbiter as AR  # noqa: E402
import dataset as D  # noqa: E402
import fold_eval as FE  # noqa: E402

try:
    import numpy  # noqa: F401
    import sklearn  # noqa: F401
    HAVE_SKLEARN = True
except ImportError:
    HAVE_SKLEARN = False


def name_in_fold(k, i):
    """A tool name whose family falls in fold k (the i-th such name)."""
    n, found = 0, -1
    while True:
        name = f"fam{n}-tool"
        if D.fold({"name": name}) == k:
            found += 1
            if found == i:
                return name
        n += 1


TEXT = ["Mounted on   Size", "/mnt/a b     10G", "/mnt/c       20G"]
ENGINE = [[0, 13], [0, 13], [0, 13]]          # "Mounted on" and "/mnt/a b" whole
MODEL = [[0, 8, 13], [0, 7, 13], [0, 13]]     # the model cuts both
LABEL = [[0, 13], [0, 7, 13], [0, 13]]        # the label: header whole, the row cut


def doc(name, engine=ENGINE, model=MODEL, label=LABEL):
    corp = {"name": name, "strategy": "aligned-columns", "lines": TEXT,
            "roles": ["header", "row", "row"], "starts": engine}
    probs = [[[c, 0.9 if c in m else 0.2] for c in (0, 7, 8, 13)] for m in model]
    cv = {"name": name, "roles": corp["roles"], "starts": model, "probs": probs}
    llm = {"name": name, "lines": TEXT, "starts": label}
    return corp, cv, llm


def data(docs, gold=None):
    c, v, l_ = zip(*docs)
    return AR.Data(list(c), list(v), "", list(l_), gold or [])


class Lines(unittest.TestCase):
    def test_training_rows_are_the_lines_exactly_one_split_gets_right(self):
        d = data([doc(name_in_fold(0, 0))])
        X, y = AR.training_rows(d, set(d.cv), "llm")
        # line 0: engine right, model wrong; line 1: model right; line 2: they agree
        self.assertEqual(y, [1, 0])
        self.assertEqual(len(X[0]), 13)

    def test_gold_target_uses_the_hand_labels(self):
        n = name_in_fold(0, 0)
        gold = [{"name": n, "line": 1, "text": TEXT[1], "starts": [0, 13], "alt": None}]
        d = data([doc(n)], gold)
        self.assertEqual(AR.training_rows(d, set(d.cv), "gold")[1], [1])

    def test_uncontested_lines_are_never_rows(self):
        n = name_in_fold(0, 0)
        corp, cv, llm = doc(n)
        cv["probs"][0] = None                    # the model did not score line 0
        d = AR.Data([corp], [cv], "", [llm], [])
        self.assertEqual(AR.training_rows(d, set(d.cv), "llm")[1], [0])
        self.assertFalse(d.contested(n, 0))

    def test_documents_without_predictions_are_left_out(self):
        corp, cv, llm = doc(name_in_fold(0, 0))
        extra, _, _ = doc(name_in_fold(1, 0))
        d = AR.Data([corp, extra], [cv], "", [llm], [])
        self.assertEqual(set(d.cv), {corp["name"]})


class Score(unittest.TestCase):
    ENGINE_SIDE = {"coef": [0.0] * 13, "intercept": 5.0}
    MODEL_SIDE = {"coef": [0.0] * 13, "intercept": -5.0}

    def test_no_arbiter_is_the_model(self):
        d = data([doc(name_in_fold(0, 0))])
        s = AR.score(None, d, set(d.cv))
        self.assertEqual((s["lines"], s["engine"], s["model"], s["arbiter"], s["switched"]), (3, 2, 2, 2, 0))

    def test_counts_switches_and_captures(self):
        better_engine = doc(name_in_fold(0, 0), label=ENGINE)       # the label agrees with the engine
        d = data([better_engine])
        s = AR.score(self.ENGINE_SIDE, d, set(d.cv))
        self.assertEqual((s["engine"], s["model"], s["arbiter"]), (3, 1, 3))
        self.assertEqual((s["switched"], s["switched_right"], s["switched_wrong"]), (2, 2, 0))
        self.assertEqual((s["engine_better"], s["rescued"], s["helped"], s["hurt"]), (1, 1, 1, 0))
        s = AR.score(self.MODEL_SIDE, d, set(d.cv))
        self.assertEqual((s["arbiter"], s["switched"], s["rescued"]), (1, 0, 0))

    def test_a_switch_that_loses_a_line_is_counted_worse(self):
        model_better = doc(name_in_fold(0, 0), label=MODEL)
        d = data([model_better])
        s = AR.score(self.ENGINE_SIDE, d, set(d.cv))
        self.assertEqual((s["switched_wrong"], s["hurt"], s["hurt_names"]), (2, 1, [model_better[0]["name"]]))

    def test_threshold_holds_back_unsure_switches(self):
        d = data([doc(name_in_fold(0, 0), label=ENGINE)])
        unsure = {"coef": [0.0] * 13, "intercept": 0.5}             # p(engine) = 0.62
        self.assertEqual(AR.score(unsure, d, set(d.cv))["switched"], 2)
        self.assertEqual(AR.score(dict(unsure, threshold=0.7), d, set(d.cv))["switched"], 0)


@unittest.skipUnless(HAVE_SKLEARN, "needs numpy and scikit-learn")
class Fit(unittest.TestCase):
    def corpus(self):
        """Ten documents in every fold: in half the engine is right where
        the two differ, in half the model is; the log-likelihood features
        tell them apart (the model is unsure exactly where it is wrong)."""
        docs = []
        for k in range(5):
            for i in range(10):
                c, v, l_ = doc(name_in_fold(k, i), label=ENGINE if i % 2 else MODEL)
                if i % 2:            # engine right: the model's cuts are unsure
                    v["probs"] = [[[x, 0.55 if x in (7, 8) else (0.9 if x in m else 0.1)]
                                   for x in (0, 7, 8, 13)] for m in MODEL]
                docs.append((c, v, l_))
        return data(docs)

    def test_nested_fit_learns_the_split_out_of_fold(self):
        d = self.corpus()
        tot, per = AR.nested(d, "llm", "0.5")
        self.assertEqual(len(per), 5)
        self.assertGreater(tot["arbiter"], tot["model"])
        self.assertGreater(tot["arbiter"], tot["engine"])
        self.assertEqual(tot["hurt"], 0)

    def test_auto_threshold_is_one_of_the_choices(self):
        d = self.corpus()
        t = AR.choose_threshold(d, set(d.cv), "llm", range(5))
        self.assertIn(t, AR.THRESHOLDS)

    def test_main_saves_a_runtime_arbiter(self):
        d = self.corpus()
        with tempfile.TemporaryDirectory() as t:
            paths = {}
            for key, rows in (("corpus", d.corp.values()), ("cv", d.cv.values()), ("llm", d.llm.values())):
                paths[key] = os.path.join(t, key + ".jsonl")
                with open(paths[key], "w", encoding="utf-8") as fh:
                    fh.writelines(json.dumps(r) + "\n" for r in rows)
            out = os.path.join(t, "arbiter-lm.json")
            AR.main(["--corpus", paths["corpus"], "--crossval", paths["cv"], "--llm", paths["llm"],
                     "--meta", t, "--target", "llm", "--threshold", "auto", "--for-model", "a test model",
                     "--save", out])
            with open(out, encoding="utf-8") as fh:
                m = json.load(fh)
        self.assertEqual(len(m["coef"]), 13)
        self.assertIn(m["threshold"], AR.THRESHOLDS)
        self.assertEqual(m["for"], "a test model")
        self.assertEqual(m["fitted"]["target"], "llm")
        self.assertNotIn("model", m)          # only --for-model provost-model pins a fingerprint


class FoldOut(unittest.TestCase):
    def test_out_learner(self):
        class A:
            learner = "both"
        self.assertEqual(FE.out_learner(A), "trees")
        A.learner = "lm"
        self.assertEqual(FE.out_learner(A), "lm")

    def test_write_out_is_what_the_arbiter_reads(self):
        eng = {"t-a": {"lines": ["a  b", ""]}}
        preds = {"lm": {"t-a": (["row", "blank"], None, [{0: 0.9, 3: 0.8}, None])}}
        out = {"lm": {"t-a": [[3, 0], None]}}
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "oof.jsonl")
            FE.write_out(p, eng, preds, out, "lm")
            rows = D.load(p)
        self.assertEqual(rows, [{"name": "t-a", "roles": ["row", "blank"], "starts": [[0, 3], None],
                                 "probs": [[[0, 0.9], [3, 0.8]], None]}])


if __name__ == "__main__":
    unittest.main()
