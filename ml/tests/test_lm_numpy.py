# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tests for the tiny LM without torch: the tokenizer (extract/model/bpe.py,
stdlib), the numpy runtime (lm_numpy.py) and the exporter's quantizers
(ml/export_lm.py). A tiny random model stands in for the real one, so nothing
is downloaded; where torch and transformers are installed, the numpy forward
pass is also checked against transformers' Llama on the same weights.

    python3 -m unittest ml.tests.test_lm_numpy -v
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "extract", "model"))
import bpe  # noqa: E402
import lm_runtime as LMR  # noqa: E402
from layout import PREDICTED, candidates  # noqa: E402

try:
    import numpy as np
    import export_lm as X
    import lm_numpy as LMN
    HAVE_NP = True
except ImportError:
    HAVE_NP = False

try:
    import torch
    from transformers import LlamaConfig, LlamaModel
    HAVE_TORCH = HAVE_NP
except ImportError:
    HAVE_TORCH = False


def tiny_tokenizer_json():
    """Every byte as a token, plus two merges and one added token."""
    alpha = bpe._byte_alphabet()
    vocab = {"<s>": 0}
    for b in range(256):
        vocab[alpha[b]] = len(vocab)
    for m in ("a b", "ab c"):
        vocab[m.replace(" ", "")] = len(vocab)
    return {"normalizer": None, "pre_tokenizer": {"type": "ByteLevel", "add_prefix_space": False, "use_regex": True},
            "added_tokens": [{"id": 0, "content": "<s>"}],
            "model": {"type": "BPE", "vocab": vocab, "merges": ["a b", "ab c"], "byte_fallback": False}}


class Tokenizer(unittest.TestCase):
    def test_gpt2_pattern(self):
        # each expected split is what transformers' ByteLevel pre-tokenizer gives
        self.assertEqual(bpe.split_gpt2("Z  9"), ["Z", " ", " ", "9"])
        self.assertEqual(bpe.split_gpt2("x  b"), ["x", " ", " b"])
        self.assertEqual(bpe.split_gpt2("a  "), ["a", "  "])
        self.assertEqual(bpe.split_gpt2("1 2"), ["1", " 2"])
        self.assertEqual(bpe.split_gpt2(" ²"), [" ²"])
        self.assertEqual(bpe.split_gpt2("a\x1c b"), ["a", "\x1c", " b"])
        self.assertEqual(bpe.split_gpt2("don't 's"), ["don", "'t", " '", "s"])

    def test_merges_by_rank_and_added_tokens(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "tokenizer.json")
            with open(p, "w", encoding="utf-8") as fh:
                json.dump(tiny_tokenizer_json(), fh)
            tok = bpe.Tokenizer.load(p)
            v = tok.vocab
            self.assertEqual(tok.encode("abc"), [v["abc"]])
            self.assertEqual(tok.encode("abd"), [v["ab"], v["d"]])
            self.assertEqual(tok.encode("x<s>abc"), [v["x"], 0, v["abc"]])
            self.assertEqual(tok(["ab", "é"]), [[v["ab"]], [v["Ã"], v["©"]]])

    def test_refuses_other_tokenizers(self):
        t = tiny_tokenizer_json()
        t["pre_tokenizer"] = {"type": "Whitespace"}
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "tokenizer.json")
            with open(p, "w", encoding="utf-8") as fh:
                json.dump(t, fh)
            with self.assertRaises(ValueError):
                bpe.Tokenizer.load(p)


CFG = {"format": LMR.NUMPY_FORMAT, "hidden": 16, "layers": 2, "heads": 4, "kv_heads": 2, "head_dim": 4,
       "intermediate": 24, "rope_theta": 10000.0, "rms_eps": 1e-5, "vocab": 259, "bos": 0, "max_tok": 64,
       "roles": PREDICTED}


def tiny_weights(seed=0):
    """Float weights in lm_numpy's layout (linear layers as torch's (out, in))."""
    r = np.random.default_rng(seed)
    h, f, kv = CFG["hidden"], CFG["intermediate"], CFG["kv_heads"] * CFG["head_dim"]
    w = {"embed.w": r.normal(0, 1, (CFG["vocab"], h)).astype(np.float32), "norm": 1 + r.normal(0, .1, h)}
    shapes = {"q": (h, h), "k": (kv, h), "v": (kv, h), "o": (h, h), "gate": (f, h), "up": (f, h), "down": (h, f)}
    for i in range(CFG["layers"]):
        w[f"l{i}.in_norm"] = 1 + r.normal(0, .1, h)
        w[f"l{i}.post_norm"] = 1 + r.normal(0, .1, h)
        for k, s in shapes.items():
            w[f"l{i}.{k}.w"] = r.normal(0, .3, s).astype(np.float32)
    for head, n in (("start", 1), ("role", len(PREDICTED))):
        w[f"{head}.w0"], w[f"{head}.b0"] = r.normal(0, .3, (h, h)), r.normal(0, .1, h)
        w[f"{head}.w1"], w[f"{head}.b1"] = r.normal(0, .3, (n, h)), r.normal(0, .1, n)
    return {k: np.asarray(v, dtype=np.float32) for k, v in w.items()}


@unittest.skipUnless(HAVE_NP, "needs numpy")
class Numpy(unittest.TestCase):
    def test_quantizers_round_trip(self):
        w = np.random.default_rng(1).normal(0, 1, (8, 128)).astype(np.float32)
        q, s = X.quant8(w)
        self.assertEqual(q.dtype, np.int8)
        self.assertLess(np.abs(LMN.dequant8(q, s).T - w).max(), np.abs(w).max() / 100)
        p, s4 = X.quant4(w)
        self.assertEqual(p.shape, (8, 64))
        back = LMN.dequant4_rows(p, s4, np.arange(8))
        self.assertLess(np.abs(back - w).max(), np.abs(w).max() / 7)

    def test_erf(self):
        import math
        xs = np.linspace(-4, 4, 81)
        self.assertLess(max(abs(a - math.erf(x)) for a, x in zip(LMN.erf(xs), xs)), 2e-7)

    def test_causal(self):
        m = LMN.NumpyLM(CFG, tiny_weights())
        full = m.hidden([0, 5, 9, 12, 7])
        self.assertEqual(full.shape, (5, CFG["hidden"]))
        self.assertTrue(np.allclose(m.hidden([0, 5, 9])[:3], full[:3], atol=1e-5))

    def test_export_load_run(self):
        w = tiny_weights()
        q = {k: v for k, v in w.items() if not k.endswith(".w")}
        q["embed.q"], q["embed.s"] = X.quant4(w["embed.w"], group=8)
        for k in [k for k in w if k.endswith(".w") and k != "embed.w"]:
            q[k[:-2] + ".q"], q[k[:-2] + ".s"] = X.quant8(w[k])
        with tempfile.TemporaryDirectory() as d:
            names = X.write(d, q, CFG, json.dumps(tiny_tokenizer_json()), shard_mb=0.01)
            self.assertGreater(len(names), 1)
            self.assertTrue(LMR.is_numpy_dir(d))
            lm = LMR.load(d)
            self.assertIsInstance(lm[0], LMN.NumpyLM)
            lines = ["Filesystem  Size  Used", "/dev/sda1   50G   20G", "", "total 3"]
            roles, probs = LMR.run(lm, lines)
            self.assertEqual(len(roles), len(lines))
            self.assertEqual(roles[2], "blank")
            self.assertTrue(all(r in PREDICTED or r == "blank" for r in roles))
            self.assertEqual(sorted(probs[0]), candidates(lines[0]))
            self.assertTrue(all(0.0 <= p <= 1.0 for p in probs[0].values()))
            # role_probs (PV-012): the same answers, plus each line's role probabilities
            r2, p2, rp = LMR.run(lm, lines, role_probs=True)
            self.assertEqual((r2, p2), (roles, probs))
            self.assertIsNone(rp[2])
            for j in (0, 1, 3):
                self.assertEqual(sorted(rp[j]), sorted(PREDICTED))
                self.assertAlmostEqual(sum(rp[j].values()), 1.0, places=5)
                self.assertEqual(max(rp[j], key=rp[j].get), roles[j])

    def test_the_numpy_runtime_never_imports_torch(self):
        here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "extract", "model")
        out = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); "
                              "import layout_model, lm_numpy, lm_encode, bpe; print('torch' in sys.modules)", here],
                             capture_output=True, text=True, check=True).stdout.strip()
        self.assertEqual(out, "False")

    def test_a_missing_or_foreign_directory_declines(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(LMR.load(d))
            with open(os.path.join(d, "config.json"), "w", encoding="utf-8") as fh:
                json.dump(dict(CFG, shards=["weights-1.npz"]), fh)
            self.assertIsNone(LMR.load(d))          # its shard is missing


@unittest.skipUnless(HAVE_TORCH, "needs numpy, torch and transformers")
class AgainstTransformers(unittest.TestCase):
    def test_numpy_forward_matches_llama(self):
        w = tiny_weights(3)
        cfg = LlamaConfig(vocab_size=CFG["vocab"], hidden_size=CFG["hidden"], intermediate_size=CFG["intermediate"],
                          num_hidden_layers=CFG["layers"], num_attention_heads=CFG["heads"],
                          num_key_value_heads=CFG["kv_heads"], rope_theta=CFG["rope_theta"],
                          rms_norm_eps=CFG["rms_eps"], max_position_embeddings=128)
        model = LlamaModel(cfg).eval()
        sd = {"embed_tokens.weight": w["embed.w"], "norm.weight": w["norm"]}
        for i in range(CFG["layers"]):
            p = f"layers.{i}."
            sd[p + "input_layernorm.weight"] = w[f"l{i}.in_norm"]
            sd[p + "post_attention_layernorm.weight"] = w[f"l{i}.post_norm"]
            for k, name in X.PROJ.items():
                sd[p + name + ".weight"] = w[f"l{i}.{k}.w"]
        model.load_state_dict({k: torch.tensor(v) for k, v in sd.items()}, strict=False)
        ids = [0, 17, 42, 99, 3, 250, 8, 8, 31]
        with torch.no_grad():
            want = model(input_ids=torch.tensor([ids])).last_hidden_state[0].numpy()
        got = LMN.NumpyLM(CFG, w).hidden(ids)
        self.assertLess(np.abs(got - want).max(), 1e-4)


if __name__ == "__main__":
    unittest.main()
