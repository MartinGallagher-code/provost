# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""The tiny-LM labeller on numpy alone: no torch, transformers or peft.

    import lm_numpy as LMN
    lm = LMN.load(path)                 # a directory ml/export_lm.py wrote
    roles, probs = LMN.run(lm, lines)   # the same answers as lm_runtime.run

ml/export_lm.py turns a trained model (ml/train_lm.py --save) into a model
directory: the LoRA adapter merged into the base model's weights, the
transformer layers it kept, and its two heads, stored at 8 bits (the
vocabulary table at 8 or 4) in weights-N.npz shards. It also writes config.json,
and tokenizer.json, which bpe.py reads. This is the same Llama forward pass
transformers runs (RMSNorm, rotary positions, grouped-query attention, a
SiLU-gated MLP), in float32, one window at a time.
"""
import json
import math
import os

import numpy as np

import bpe
import lm_encode as LME
from layout import PREDICTED, candidates, is_blank

FORMAT = LME.NUMPY_FORMAT


def dequant8(q, s):
    """int8 rows times their scales, as (in, out) for x @ w."""
    return (q.astype(np.float32) * s.astype(np.float32)[:, None]).T.copy()


class Linear:
    """layer(x) = x @ W.T for one linear layer, W as torch's (out, in). At 8 bits it
    stays int8 in memory (a quarter of float32) and is widened for each
    product; the row scales apply to the product's columns instead."""

    def __init__(self, w, name):
        if name + ".w" in w:                       # float, for checking an export
            self.w, self.s = w[name + ".w"].astype(np.float32), None
        else:
            self.w, self.s = w[name + ".q"], w[name + ".s"].astype(np.float32)

    def __call__(self, x):
        y = x @ self.w.astype(np.float32, copy=False).T
        return y if self.s is None else y * self.s


def dequant4_rows(packed, s, rows):
    """Rows of a 4-bit table: two values per byte, low nibble first, offset
    by 8; one scale per row and group of `group` columns."""
    p = packed[rows]
    lo = (p & 0x0F).astype(np.int8) - 8
    hi = (p >> 4).astype(np.int8) - 8
    q = np.empty((p.shape[0], p.shape[1] * 2), dtype=np.float32)
    q[:, 0::2] = lo
    q[:, 1::2] = hi
    sc = s[rows].astype(np.float32)
    return (q.reshape(q.shape[0], sc.shape[1], -1) * sc[:, :, None]).reshape(q.shape[0], -1)


def erf(x):
    """Abramowitz and Stegun 7.1.26 (|error| < 1.5e-7): numpy has no erf."""
    s = np.sign(x)
    a = np.abs(x)
    t = 1.0 / (1.0 + 0.3275911 * a)
    y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t
               + 0.254829592) * t * np.exp(-a * a)
    return s * y


def gelu(x):
    return 0.5 * x * (1.0 + erf(x / math.sqrt(2.0)))


class NumpyLM:
    numpy = True

    def __init__(self, cfg, w):
        self.cfg = self.meta = cfg
        self.h = cfg["hidden"]
        self.nh, self.nkv, self.hd = cfg["heads"], cfg["kv_heads"], cfg["head_dim"]
        self.eps = cfg["rms_eps"]
        self.embed = {k: w[k] for k in ("embed.q", "embed.s", "embed.w") if k in w}
        self.layers = []
        for i in range(cfg["layers"]):
            p = f"l{i}."
            self.layers.append({
                "in": w[p + "in_norm"].astype(np.float32),
                "post": w[p + "post_norm"].astype(np.float32),
                **{k: Linear(w, p + k) for k in ("q", "k", "v", "o", "gate", "up", "down")},
            })
        self.norm = w["norm"].astype(np.float32)
        self.heads = {k: [w[f"{k}.{j}"].astype(np.float32) for j in ("w0", "b0", "w1", "b1")]
                      for k in ("start", "role")}
        half = self.hd // 2
        self.inv_freq = 1.0 / (cfg["rope_theta"] ** (np.arange(0, half, dtype=np.float64) * 2 / self.hd))

    def _norm(self, x, w):
        return (x / np.sqrt(np.mean(x * x, axis=-1, keepdims=True) + self.eps)) * w

    def _rope(self, t):
        f = np.outer(np.arange(t, dtype=np.float64), self.inv_freq)
        emb = np.concatenate([f, f], axis=-1)
        return np.cos(emb).astype(np.float32), np.sin(emb).astype(np.float32)

    @staticmethod
    def _rotate(x, cos, sin):
        half = x.shape[-1] // 2
        rot = np.concatenate([-x[..., half:], x[..., :half]], axis=-1)
        return x * cos + rot * sin

    def _embed(self, ids):
        e = self.embed
        if "embed.w" in e:
            return e["embed.w"][ids].astype(np.float32)
        if e["embed.q"].dtype == np.int8:
            return e["embed.q"][ids].astype(np.float32) * e["embed.s"][ids].astype(np.float32)[:, None]
        return dequant4_rows(e["embed.q"], e["embed.s"], ids)

    def hidden(self, ids):
        """(len(ids), hidden): the backbone's last hidden states (after the
        final norm), for one sequence."""
        t = len(ids)
        x = self._embed(np.asarray(ids))
        cos, sin = self._rope(t)
        mask = np.triu(np.full((t, t), -np.inf, dtype=np.float32), 1)
        rep = self.nh // self.nkv
        for L in self.layers:
            a = self._norm(x, L["in"])
            q = L["q"](a).reshape(t, self.nh, self.hd).transpose(1, 0, 2)
            k = L["k"](a).reshape(t, self.nkv, self.hd).transpose(1, 0, 2)
            v = L["v"](a).reshape(t, self.nkv, self.hd).transpose(1, 0, 2)
            q = self._rotate(q, cos, sin)
            k = np.repeat(self._rotate(k, cos, sin), rep, axis=0)
            v = np.repeat(v, rep, axis=0)
            s = q @ k.transpose(0, 2, 1) / math.sqrt(self.hd) + mask
            s = np.exp(s - s.max(axis=-1, keepdims=True))
            s /= s.sum(axis=-1, keepdims=True)
            o = (s @ v).transpose(1, 0, 2).reshape(t, self.nh * self.hd)
            x = x + L["o"](o)
            m = self._norm(x, L["post"])
            g = L["gate"](m)
            x = x + L["down"]((g / (1.0 + np.exp(-g))) * L["up"](m))
        return self._norm(x, self.norm)

    def head(self, name, h):
        w0, b0, w1, b1 = self.heads[name]
        return gelu(h @ w0.T + b0) @ w1.T + b1


def load(path):
    """(NumpyLM, encoder) from a model directory; raises if it can't."""
    with open(os.path.join(path, "config.json"), encoding="utf-8") as fh:
        cfg = json.load(fh)
    if cfg.get("format") != FORMAT:
        raise ValueError(f"{path}: not a {FORMAT} model")
    if cfg.get("roles", PREDICTED) != PREDICTED:
        raise ValueError(f"{path}: its roles are not this provost's")
    w = {}
    for shard in cfg["shards"]:
        with np.load(os.path.join(path, shard), allow_pickle=False) as z:
            w.update({k: z[k] for k in z.files})
    tok = bpe.Tokenizer.load(os.path.join(path, "tokenizer.json"))
    return NumpyLM(cfg, w), LME.Encoder(tok, cfg["bos"], cfg["max_tok"])


def run(lm, lines):
    """lm_runtime.run's answers, from the numpy model."""
    model, enc = lm
    roles = ["blank" if is_blank(ln) else None for ln in lines]
    probs = [None] * len(lines)
    for j, ln in enumerate(lines):
        cs = candidates(ln)
        if cs:
            probs[j] = {c: 0.0 for c in cs}
    for it in LME.items(enc, {"lines": lines}, with_targets=False):
        h = model.hidden(it["ids"])
        if it["cpos"]:
            z = model.head("start", h[it["cpos"]])[:, 0]
            for (j, c), q in zip(it["cref"], 1.0 / (1.0 + np.exp(-z))):
                probs[j][c] = float(q)
        if it["rpos"]:
            for j, k in zip(it["rref"], model.head("role", h[it["rpos"]]).argmax(-1)):
                roles[j] = PREDICTED[int(k)]
    return [r or "skip" for r in roles], probs
