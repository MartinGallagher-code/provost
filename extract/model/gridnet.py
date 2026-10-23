# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""GridNet at capture time: the axial-transformer layout model (trained by
ml/train_grid.py) evaluated with numpy alone, no torch.

    import gridnet
    net = gridnet.load()                    # None when numpy or the weights are missing
    roles, probs = gridnet.run(net, lines)  # per line: role, {candidate: p} or None

Weights: gridnet.npz next to this file (float16, written by
ml/export_grid.py). The forward pass mirrors train_grid.GridNet exactly;
ml/tests checks the two agree.
"""
import math
import os

try:
    import numpy as np
except ImportError:  # the tree model needs nothing; this one needs numpy
    np = None

from layout import PREDICTED, candidates, is_blank

HERE = os.path.dirname(os.path.abspath(__file__))
WEIGHTS = os.path.join(HERE, "gridnet.npz")
W_MAX, H_MAX, VOID = 240, 64, 1


def char_id(ch):
    o = ord(ch)
    if 32 <= o < 127:
        return o - 30
    if ch == "\t":
        return 97
    if 0x2500 <= o <= 0x257F:
        return 98
    if ch.isdigit():
        return 99
    if ch.isalpha():
        return 100
    if ch.isspace():
        return 101
    return 102


SPACE = char_id(" ")


def load(path=WEIGHTS):
    if np is None or not os.path.exists(path):
        return None
    z = np.load(path)
    net = {k: z[k].astype(np.float32) for k in z.files if not k.startswith("_")}
    net["_heads"] = int(z["_heads"])
    net["_layers"] = int(z["_layers"])
    net["_line_layers"] = int(z["_line_layers"])
    return net


def _ln(x, g, b, eps=1e-5):
    m = x.mean(-1, keepdims=True)
    v = ((x - m) ** 2).mean(-1, keepdims=True)
    return (x - m) / np.sqrt(v + eps) * g + b


def _gelu(x):
    return 0.5 * x * (1.0 + _erf(x / math.sqrt(2.0)))


def _erf(x):
    """erf to ~1e-7 (Numerical Recipes' erfc), elementwise; torch's GELU is exact."""
    a = np.abs(x)
    t = 1.0 / (1.0 + 0.5 * a)
    y = 1.0 - t * np.exp(-a * a - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (
        0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (
            1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))))
    return np.sign(x) * y


def _conv2d(x, w, b, pad, dil=(1, 1), groups=1):
    """x: H,W,C (channels last); w: Cout, Cin/groups, kh, kw (torch layout)."""
    H, W, C = x.shape
    co, ci, kh, kw = w.shape
    xp = np.pad(x, ((pad[0], pad[0]), (pad[1], pad[1]), (0, 0)))
    out = np.zeros((H, W, co), dtype=np.float32)
    for i in range(kh):
        for j in range(kw):
            sl = xp[i * dil[0]:i * dil[0] + H, j * dil[1]:j * dil[1] + W, :]
            if groups == 1:
                out += sl @ w[:, :, i, j].T
            else:  # depthwise
                out += sl * w[:, 0, i, j]
    return out + b


def _mha(x, pad, p, heads):
    """x: N,L,D; pad: N,L bool. torch.nn.MultiheadAttention, batch_first."""
    N, L, D = x.shape
    qkv = x @ p["in_proj_weight"].T + p["in_proj_bias"]
    q, k, v = np.split(qkv, 3, axis=-1)
    hd = D // heads

    def split(t):
        return t.reshape(N, L, heads, hd).transpose(0, 2, 1, 3)
    q, k, v = split(q), split(k), split(v)
    att = q @ k.transpose(0, 1, 3, 2) / math.sqrt(hd)
    m = pad.copy()
    m[:, 0] = False
    att = np.where(m[:, None, None, :], -1e9, att)
    att = att - att.max(-1, keepdims=True)
    att = np.exp(att)
    att /= att.sum(-1, keepdims=True)
    y = (att @ v).transpose(0, 2, 1, 3).reshape(N, L, D)
    return y @ p["out_proj.weight"].T + p["out_proj.bias"]


def _sub(net, prefix):
    return {k[len(prefix):]: v for k, v in net.items() if k.startswith(prefix)}


def _sinusoid(n, d):
    pos = np.arange(n, dtype=np.float32)[:, None]
    div = np.exp(np.arange(0, d, 2, dtype=np.float32) * (-math.log(10000.0) / d))
    pe = np.zeros((n, d), dtype=np.float32)
    pe[:, 0::2] = np.sin(pos * div)
    pe[:, 1::2] = np.cos(pos * div)
    return pe


def forward(net, grid):
    """grid: H,W int ids (VOID past line ends). -> (start logits H,W; role logits H,R)."""
    H, W = grid.shape
    heads = net["_heads"]
    x = net["emb.weight"][grid]
    x = x + _gelu(_conv2d(x, net["inp.weight"], net["inp.bias"], (1, 1)))
    d = x.shape[-1]
    x = x + _sinusoid(W_MAX + 8, d)[:W][None, :, :] + net["ypos.weight"][np.minimum(np.arange(H), H_MAX - 1)][:, None, :]
    pad = np.zeros((H, W), dtype=bool)
    for li in range(net["_layers"]):
        p = _sub(net, f"layers.{li}.")
        y = _ln(x, p["ln_r.weight"], p["ln_r.bias"])
        a = _gelu(_conv2d(y, p["row.a.weight"], p["row.a.bias"], (0, 2), groups=d))
        b = _gelu(_conv2d(y, p["row.b.weight"], p["row.b.bias"], (0, 8), (1, 4), groups=d))
        x = x + (a + b) @ p["row.mix.weight"].T + p["row.mix.bias"]
        y = _ln(x, p["ln_c.weight"], p["ln_c.bias"]).transpose(1, 0, 2)
        y = _mha(y, pad.T, _sub(p, "col."), heads)
        x = x + y.transpose(1, 0, 2)
        y = _ln(x, p["ln_f.weight"], p["ln_f.bias"])
        y = y + _conv2d(y, p["local.weight"], p["local.bias"], (0, 1), groups=d)
        x = x + _gelu(y @ p["ff.0.weight"].T + p["ff.0.bias"]) @ p["ff.3.weight"].T + p["ff.3.bias"]
    x = _ln(x, net["ln.weight"], net["ln.bias"])
    starts = (x @ net["start.weight"].T + net["start.bias"])[..., 0]
    real = ((grid > VOID) & (grid != SPACE))[..., None].astype(np.float32)
    n = real.sum(1)
    mean = (x * real).sum(1) / np.maximum(n, 1)
    mx = np.maximum((x * real - (1 - real) * 1e4).max(1), -50)
    blank = (n == 0).astype(np.float32)
    h = np.concatenate([mean, mx, blank], -1) @ net["pool.weight"].T + net["pool.bias"]
    for li in range(net["_line_layers"]):
        p = _sub(net, f"lines.layers.{li}.")
        y = _ln(h, p["norm1.weight"], p["norm1.bias"])[None]
        h = h + _mha(y, np.zeros((1, H), dtype=bool), _sub(p, "self_attn."), heads)[0]
        y = _ln(h, p["norm2.weight"], p["norm2.bias"])
        h = h + np.maximum(y @ p["linear1.weight"].T + p["linear1.bias"], 0) @ p["linear2.weight"].T \
            + p["linear2.bias"]
    return starts, h @ net["role.weight"].T + net["role.bias"]


def encode(lines):
    W = min(W_MAX, max([len(ln) for ln in lines] + [1]))
    grid = np.full((len(lines), W), VOID, dtype=np.int64)
    for h, ln in enumerate(lines):
        for w, ch in enumerate(ln[:W]):
            grid[h, w] = char_id(ch)
    return grid


def run(net, lines):
    """-> (roles, probs): per line its role, and for lines with field-start
    candidates {candidate: p(start)}."""
    roles = ["blank" if is_blank(ln) else None for ln in lines]
    sp = np.zeros((len(lines), W_MAX), dtype=np.float32)
    for lo in range(0, len(lines), H_MAX):
        chunk = lines[lo:lo + H_MAX]
        s, r = forward(net, encode(chunk))
        sp[lo:lo + len(chunk), :s.shape[1]] = 1 / (1 + np.exp(-s))
        for h, k in enumerate(r.argmax(-1).tolist()):
            if roles[lo + h] is None:
                roles[lo + h] = PREDICTED[k]
    probs = []
    for j, ln in enumerate(lines):
        c = candidates(ln)
        probs.append({i: float(sp[j, i]) if i < W_MAX else 0.0 for i in c} if c else None)
    return roles, probs
