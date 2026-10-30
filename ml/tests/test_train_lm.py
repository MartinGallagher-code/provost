# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tests for the tiny-LM labeller (ml/train_lm.py) on a tiny random model and
a character tokenizer: nothing is downloaded. Skipped where torch,
transformers or peft is not installed (CI's quick checks are stdlib only).

    python3 -m unittest ml.tests.test_train_lm -v
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "extract", "model"))

try:
    import torch
    import transformers  # noqa: F401
    import peft  # noqa: F401
    import train_lm as LM
    HAVE = True
except ImportError:
    HAVE = False

from layout import PREDICTED, candidates  # noqa: E402


def char_tok(xs):
    return [[min(ord(ch), 255) + 1 for ch in x] for x in xs]


def tiny_backbone():
    from transformers import LlamaConfig, LlamaModel
    torch.manual_seed(0)
    cfg = LlamaConfig(vocab_size=260, hidden_size=32, intermediate_size=64, num_hidden_layers=2,
                      num_attention_heads=4, num_key_value_heads=2, max_position_embeddings=2048)
    return LlamaModel(cfg)


DOC = {"name": "df-h", "lines": ["Filesystem  Size  Mounted on", "/dev/sda1   50G   /", "", "Total: 1"],
       "roles": ["header", "row", "blank", "skip"],
       "starts": [[0, 12, 18], [0, 12, 18], None, None]}


@unittest.skipUnless(HAVE, "needs torch, transformers and peft")
class Encoding(unittest.TestCase):
    def setUp(self):
        self.enc = LM.Encoder(char_tok, bos=0, max_tok=40)

    def test_every_candidate_begins_a_token(self):
        for ln in DOC["lines"]:
            ids, cand = self.enc.lines([ln])[0]
            self.assertEqual([c for c, _ in cand], candidates(ln))
            for c, p in cand:   # a character tokenizer: token p is character c
                self.assertEqual(ids[p], ord(ln[c]) + 1)

    def test_echo_second_copy_positions(self):
        enc, wins = self.enc.windows(DOC["lines"])
        seq, pos = self.enc.sequence(enc, *wins[0])
        sep = seq.index(char_tok(["="])[0][0])
        for j, cs, e in pos:
            self.assertGreater(e, sep)                       # read from the second copy
            self.assertEqual(seq[e], char_tok(["\n"])[0][0])  # a line's last token
            for c, p in cs:
                self.assertEqual(seq[p], ord(DOC["lines"][j][c]) + 1)

    def test_long_documents_split_into_windows(self):
        lines = [f"row{i}  value{i}" for i in range(20)]
        enc, wins = self.enc.windows(lines)
        self.assertGreater(len(wins), 1)
        self.assertEqual(wins[0][0], 0)
        self.assertEqual(wins[-1][1], len(lines))
        for (a, b), (c, _) in zip(wins, wins[1:]):
            self.assertEqual(b, c)

    def test_targets(self):
        its = LM.items(LM.Encoder(char_tok, bos=0, max_tok=400), DOC)
        self.assertEqual(len(its), 1)
        it = its[0]
        self.assertEqual(len(it["rpos"]), 3)                 # the blank line is not predicted
        self.assertEqual(it["rgold"][0], PREDICTED.index("header"))
        gold = dict(zip(it["cref"], it["cgold"]))
        self.assertEqual(gold[(0, 12)], 1.0)
        self.assertEqual(gold[(0, 26)], 0.0)                 # "on" of "Mounted on"
        self.assertEqual(gold[(3, 7)], -1.0)                 # unknown starts are masked


@unittest.skipUnless(HAVE, "needs torch, transformers and peft")
class Model(unittest.TestCase):
    def test_training_lowers_the_loss_and_predicts_the_contract(self):
        torch.manual_seed(0)
        model, _ = LM.build(lora=4, backbone=tiny_backbone())
        enc = LM.Encoder(char_tok, bos=0, max_tok=64)
        its = LM.items(enc, DOC) * 4
        before = LM.val_loss(model, its)
        LM.train(model, its, epochs=8, lr=3e-3, head_lr=3e-3, log=lambda m: None)
        self.assertLess(LM.val_loss(model, its), before)
        roles, starts, probs = LM.predict_doc(model, enc, DOC)
        self.assertEqual(len(roles), len(DOC["lines"]))
        self.assertEqual(roles[2], "blank")
        self.assertTrue(all(r in PREDICTED or r == "blank" for r in roles))
        self.assertEqual(sorted(probs[0]), candidates(DOC["lines"][0]))
        self.assertIsNone(probs[2])
        self.assertEqual(starts[0], [c for c, q in probs[0].items() if q > 0.5])

    def test_start_step_resumes_where_a_run_stopped(self):
        model, _ = LM.build(lora=4, backbone=tiny_backbone())
        enc = LM.Encoder(char_tok, bos=0, max_tok=64)
        its = LM.items(enc, DOC) * 4
        nb = sum(1 for _ in LM.batches(its, False, 64))
        before = {n: p.detach().clone() for n, p in model.named_parameters() if p.requires_grad}
        LM.train(model, its, epochs=2, lr=3e-3, log=lambda m: None, budget=64, start=2 * nb)
        self.assertTrue(all(torch.equal(p, before[n]) for n, p in model.named_parameters() if n in before))
        with tempfile.TemporaryDirectory() as d:
            LM.train(model, its, epochs=2, lr=3e-3, log=lambda m: None, budget=64, start=nb + 1,
                     ckpt=d, ckpt_every=1)
            with open(os.path.join(d, "last", "config.json"), encoding="utf-8") as fh:
                self.assertEqual(json.load(fh)["step"], 2 * nb)
        self.assertFalse(all(torch.equal(p, before[n]) for n, p in model.named_parameters() if n in before))

    def test_lora_trains_only_the_adapter_and_heads(self):
        model, _ = LM.build(lora=4, backbone=tiny_backbone())
        names = [n for n, p in model.named_parameters() if p.requires_grad]
        self.assertTrue(names)
        self.assertTrue(all("lora_" in n or not n.startswith("backbone.") for n in names))

    def test_save_keeps_only_the_trained_weights(self):
        model, _ = LM.build(lora=4, backbone=tiny_backbone())
        model.meta = {"base": "tiny"}
        with tempfile.TemporaryDirectory() as d:
            LM.save(model, d)
            w = torch.load(os.path.join(d, "weights.pt"))
            self.assertEqual(set(w), {n for n, p in model.named_parameters() if p.requires_grad})
            fresh, _ = LM.build(lora=4, backbone=tiny_backbone())
            fresh.load_state_dict(w, strict=False)
            for n, p in fresh.named_parameters():
                if n in w:
                    self.assertTrue(torch.equal(p, w[n]))


if __name__ == "__main__":
    unittest.main()
