#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""GridNet: a small axial transformer over the character grid, the layout
model that learns its own features (PyTorch, CPU is enough).

The capture is a grid of characters (lines x columns). Each layer mixes every
cell with its neighbours along the line (dilated convolutions: what is this
token, where does it end) and attends down its whole column (is this a gutter
in every row, does the header word sit over this value). Nothing about alignment, timestamps or
units is hand-coded: the tree model's features (features.py) are not used.

Two heads, the same outputs as the tree model so the decoder, the scoring
and provost's runtime can stay as they are:
  * starts: one logit per cell, scored at the field-start candidates;
  * roles: each line pooled across its width, then a small transformer down
    the lines.

Trained on the LLM teacher's labels (ml/llm/to_corpus.py); crossval.py
--learner grid scores it like the trees. Usage:

    python3 ml/train_grid.py --corpus ml/data/corpus-llm.jsonl --save ml/models/gridnet.pt
"""
import argparse
import functools
import math
import os
import random
import sys
import time

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extract", "model"))
import dataset as D  # noqa: E402
import decode as DEC  # noqa: E402
from features import cand_features  # noqa: E402
from layout import PREDICTED, candidates, is_blank  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
print = functools.partial(print, flush=True)  # noqa: A001
W_MAX = 240          # columns seen; candidates beyond are scored as misses
H_MAX = 64           # lines per training crop (the corpus is shorter)
VOID = 1             # a cell past the end of its line
VOCAB = 104
CELLS_PER_BATCH = 24000
NF = 49              # the tree model's candidate features (features.py), for hybrid=True


def char_id(ch):
    o = ord(ch)
    if 32 <= o < 127:
        return o - 30          # 2..96
    if ch == "\t":
        return 97
    if 0x2500 <= o <= 0x257F:
        return 98              # box drawing
    if ch.isdigit():
        return 99
    if ch.isalpha():
        return 100
    if ch.isspace():
        return 101
    return 102


def cell_features(lines, W):
    """H,W,NF: the tree model's features at each field-start candidate,
    squashed (sign * log1p) so counts and offsets sit near the unit range."""
    out = np.zeros((len(lines), W, NF), dtype=np.float32)
    for h in range(len(lines)):
        for c, f in cand_features(lines, h):
            if c < W:
                out[h, c] = f
    return np.sign(out) * np.log1p(np.abs(out))


def encode(ex, lo=0, hi=None, shift=0, with_targets=True, feats=False):
    lines = [" " * shift + ln for ln in ex["lines"][lo:hi]]
    H = len(lines)
    W = min(W_MAX, max([len(ln) for ln in lines] + [1]))
    grid = np.full((H, W), VOID, dtype=np.int64)
    for h, ln in enumerate(lines):
        for w, ch in enumerate(ln[:W]):
            grid[h, w] = char_id(ch)
    feat = cell_features(lines, W) if feats else None
    if not with_targets:
        return grid, None, None, None, feat
    role = np.full(H, -1, dtype=np.int64)
    smask = np.zeros((H, W), dtype=np.float32)
    sgold = np.zeros((H, W), dtype=np.float32)
    for h, ln in enumerate(lines):
        r = ex["roles"][lo + h]
        if r in PREDICTED and not is_blank(ln):
            role[h] = PREDICTED.index(r)
        st = ex["starts"][lo + h]
        if st:
            for c in candidates(ln):
                if c < W:
                    smask[h, c] = 1.0
            for s in st:
                if s + shift < W:
                    sgold[h, s + shift] = 1.0
    return grid, role, smask, sgold, feat


def collate(items):
    H = max(g.shape[0] for g, *_ in items)
    W = max(g.shape[1] for g, *_ in items)
    B = len(items)
    grid = torch.zeros(B, H, W, dtype=torch.long)          # 0 = batch padding
    role = torch.full((B, H), -1, dtype=torch.long)
    smask = torch.zeros(B, H, W)
    sgold = torch.zeros(B, H, W)
    feat = torch.zeros(B, H, W, NF) if items[0][4] is not None else None
    for b, (g, r, m, s, f) in enumerate(items):
        h, w = g.shape
        grid[b, :h, :w] = torch.from_numpy(g)
        if feat is not None:
            feat[b, :h, :w] = torch.from_numpy(f)
        if r is not None:
            role[b, :h] = torch.from_numpy(r)
            smask[b, :h, :w] = torch.from_numpy(m)
            sgold[b, :h, :w] = torch.from_numpy(s)
    return grid, role, smask, sgold, feat


def sinusoid(n, d):
    pos = torch.arange(n, dtype=torch.float32).unsqueeze(1)
    div = torch.exp(torch.arange(0, d, 2, dtype=torch.float32) * (-math.log(10000.0) / d))
    pe = torch.zeros(n, d)
    pe[:, 0::2] = torch.sin(pos * div)
    pe[:, 1::2] = torch.cos(pos * div)
    return pe


def _attend(attn, x, pad):
    """x: N,L,D; pad: N,L (True = padding). Fully padded sequences attend
    to their first position so softmax never sees an all-masked row."""
    m = pad.clone()
    m[:, 0] = False
    y, _ = attn(x, x, x, key_padding_mask=m, need_weights=False)
    return y


class RowConv(nn.Module):
    """Mixing along a line: depthwise convolutions, dilation 1 and 4 (each
    layer sees ~10 characters either side). Lines are ~10x wider than
    captures are tall, so attention along them would cost most of the time."""
    def __init__(self, d):
        super().__init__()
        self.a = nn.Conv2d(d, d, (1, 5), padding=(0, 2), groups=d)
        self.b = nn.Conv2d(d, d, (1, 5), padding=(0, 8), dilation=(1, 4), groups=d)
        self.mix = nn.Linear(d, d)

    def forward(self, x, pad):
        y = x.permute(0, 3, 1, 2)
        y = F.gelu(self.a(y)) + F.gelu(self.b(y))
        return self.mix(y.permute(0, 2, 3, 1))


class AxialLayer(nn.Module):
    def __init__(self, d, heads, drop):
        super().__init__()
        self.ln_r, self.ln_c, self.ln_f = nn.LayerNorm(d), nn.LayerNorm(d), nn.LayerNorm(d)
        self.row = RowConv(d)
        self.col = nn.MultiheadAttention(d, heads, dropout=drop, batch_first=True)
        self.local = nn.Conv2d(d, d, (1, 3), padding=(0, 1), groups=d)
        self.ff = nn.Sequential(nn.Linear(d, 2 * d), nn.GELU(), nn.Dropout(drop), nn.Linear(2 * d, d))
        self.drop = nn.Dropout(drop)

    def forward(self, x, pad):
        B, H, W, Dm = x.shape
        x = x + self.drop(self.row(self.ln_r(x), pad))
        y = self.ln_c(x).permute(0, 2, 1, 3).reshape(B * W, H, Dm)
        y = _attend(self.col, y, pad.permute(0, 2, 1).reshape(B * W, H))
        x = x + self.drop(y.reshape(B, W, H, Dm).permute(0, 2, 1, 3))
        y = self.ln_f(x)
        y = y + self.local(y.permute(0, 3, 1, 2)).permute(0, 2, 3, 1)
        x = x + self.drop(self.ff(y))
        return x.masked_fill(pad.unsqueeze(-1), 0.0)


class GridNet(nn.Module):
    def __init__(self, d=64, heads=4, layers=4, line_layers=2, drop=0.0, hybrid=False):
        super().__init__()
        self.hybrid = hybrid
        self.feat = nn.Linear(NF, d) if hybrid else None
        self.emb = nn.Embedding(VOCAB, d, padding_idx=0)
        self.inp = nn.Conv2d(d, d, (3, 3), padding=1)
        self.register_buffer("xpos", sinusoid(W_MAX + 8, d), persistent=False)
        self.ypos = nn.Embedding(H_MAX, d)
        self.layers = nn.ModuleList([AxialLayer(d, heads, drop) for _ in range(layers)])
        self.ln = nn.LayerNorm(d)
        self.start = nn.Linear(d, 1)
        self.pool = nn.Linear(2 * d + 1, d)
        enc = nn.TransformerEncoderLayer(d, heads, 2 * d, drop, batch_first=True, norm_first=True)
        self.lines = nn.TransformerEncoder(enc, line_layers, enable_nested_tensor=False)
        self.role = nn.Linear(d, len(PREDICTED))

    def forward(self, grid, feat=None):
        B, H, W = grid.shape
        pad = grid == 0
        x = self.emb(grid)
        if self.hybrid:
            x = x + self.feat(feat)
        x = x + F.gelu(self.inp(x.permute(0, 3, 1, 2))).permute(0, 2, 3, 1)
        ys = torch.arange(H).clamp(max=H_MAX - 1)
        x = x + self.xpos[:W].view(1, 1, W, -1) + self.ypos(ys).view(1, H, 1, -1)
        x = x.masked_fill(pad.unsqueeze(-1), 0.0)
        for layer in self.layers:
            x = layer(x, pad)
        x = self.ln(x)
        starts = self.start(x).squeeze(-1)
        real = ((grid > VOID) & (grid != char_id(" "))).unsqueeze(-1).float()
        n = real.sum(2)
        mean = (x * real).sum(2) / n.clamp(min=1)
        mx = (x * real - (1 - real) * 1e4).amax(2).clamp(min=-50)
        blank = (n == 0).float()
        h = self.pool(torch.cat([mean, mx, blank], -1))
        line_pad = pad.all(2)
        lp = line_pad.clone()
        lp[:, 0] = False
        h = self.lines(h, src_key_padding_mask=lp)
        return starts, self.role(h)


DIGITS, LOWER, UPPER = "0123456789", "abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def augment(ex):
    """A training copy with the same layout and different text: digits
    redrawn, some letters redrawn (case kept), and sometimes one gutter
    widened in every line. Labels move with the text. The model can't
    memorise a tool's tokens or its exact column positions."""
    lines = []
    for ln in ex["lines"]:
        out = []
        for ch in ln:
            if ch in DIGITS and random.random() < 0.7:
                ch = random.choice(DIGITS)
            elif ch in LOWER and random.random() < 0.25:
                ch = random.choice(LOWER)
            elif ch in UPPER and random.random() < 0.25:
                ch = random.choice(UPPER)
            out.append(ch)
        lines.append("".join(out))
    starts = [list(s) if s else s for s in ex["starts"]]
    if random.random() < 0.5:
        width = max([len(ln) for ln in lines] + [0])
        gut = [c for c in range(1, width)
               if all(len(ln) <= c or (ln[c] == " " and ln[c - 1] == " ") for ln in lines)
               and sum(len(ln.rstrip()) > c for ln in lines) >= 2]
        if gut:
            c, k = random.choice(gut), random.randint(1, 3)
            lines = [ln[:c] + " " * k + ln[c:] if len(ln) > c else ln for ln in lines]
            starts = [[x + k if x >= c else x for x in s] if s else s for s in starts]
    return {**ex, "lines": lines, "starts": starts}


def batches(examples, train, feats=False):
    items = []
    for e in examples:
        if train:
            e = augment(e)
        n = len(e["lines"])
        shift = random.choice([0, 0, 0, 1, 2, 4]) if train else 0
        if n > H_MAX:
            lo = random.randint(0, n - H_MAX) if train else 0
            items.append(encode(e, lo, lo + H_MAX, shift, feats=feats))
        else:
            items.append(encode(e, shift=shift, feats=feats))
    order = sorted(range(len(items)), key=lambda k: (items[k][0].shape[1], items[k][0].shape[0]))
    groups, cur, cells = [], [], 0
    for k in order:
        g = items[k][0]
        h = max([items[j][0].shape[0] for j in cur] + [g.shape[0]])
        w = max([items[j][0].shape[1] for j in cur] + [g.shape[1]])
        if cur and h * w * (len(cur) + 1) > CELLS_PER_BATCH:
            groups.append(cur)
            cur = []
        cur.append(k)
    if cur:
        groups.append(cur)
    if train:
        random.shuffle(groups)
    for g in groups:
        yield collate([items[k] for k in g])


def loss_of(model, grid, role, smask, sgold, feat=None):
    s_logit, r_logit = model(grid, feat)
    lr = F.cross_entropy(r_logit.reshape(-1, len(PREDICTED)), role.reshape(-1), ignore_index=-1)
    ls = (F.binary_cross_entropy_with_logits(s_logit, sgold, reduction="none") * smask).sum() \
        / smask.sum().clamp(min=1)
    return lr + ls


@torch.no_grad()
def val_loss(model, examples):
    model.eval()
    tot, n = 0.0, 0
    for grid, role, smask, sgold, feat in batches(examples, False, model.hybrid):
        tot += loss_of(model, grid, role, smask, sgold, feat).item()
        n += 1
    return tot / max(1, n)


def train(model, examples, epochs, val=None, lr=2e-3, log=print):
    """AdamW + one-cycle; with val, keep the epoch with the lowest val loss."""
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=0.01)
    nb = sum(1 for _ in batches(examples, False))
    # shifted training copies can batch a little differently from the count
    total = int(epochs * nb * 1.1) + 20
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=lr, total_steps=total)
    best = (float("inf"), 0, None)
    for ep in range(epochs):
        model.train()
        t0, tot, k = time.time(), 0.0, 0
        for grid, role, smask, sgold, feat in batches(examples, True, model.hybrid):
            loss = loss_of(model, grid, role, smask, sgold, feat)
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            if sched.last_epoch < total - 1:
                sched.step()
            tot, k = tot + loss.item(), k + 1
        msg = f"    epoch {ep + 1}/{epochs}  loss {tot / max(1, k):.4f}  ({time.time() - t0:.0f}s)"
        if val:
            v = val_loss(model, val)
            msg += f"  val {v:.4f}"
            if v < best[0]:
                best = (v, ep + 1, {n: t.clone() for n, t in model.state_dict().items()})
        log(msg)
    if val:
        model.load_state_dict(best[2])
        log(f"    kept epoch {best[1]} (lowest validation loss)")


@torch.no_grad()
def predict_doc(model, ex, decoder=False, score_lines=None):
    """(roles, starts, probs) like crossval.predict_doc. score_lines: which
    lines get starts (default: every line with field-start candidates)."""
    model.eval()
    lines = ex["lines"]
    roles = ["blank" if is_blank(ln) else None for ln in lines]
    sp = np.zeros((len(lines), W_MAX), dtype=np.float32)
    for lo in range(0, max(1, len(lines)), H_MAX):
        hi = min(len(lines), lo + H_MAX)
        if lo >= hi:
            break
        grid, _, _, _, feat = encode(ex, lo, hi, with_targets=False, feats=model.hybrid)
        s, r = model(torch.from_numpy(grid).unsqueeze(0),
                     None if feat is None else torch.from_numpy(feat).unsqueeze(0))
        p = torch.sigmoid(s[0]).numpy()
        sp[lo:hi, :p.shape[1]] = p
        for h, k in enumerate(r[0].argmax(-1).tolist()):
            if roles[lo + h] is None:
                roles[lo + h] = PREDICTED[k]
    starts, probs = [None] * len(lines), [None] * len(lines)
    for j, ln in enumerate(lines):
        if score_lines is not None and not score_lines[j]:
            continue
        cands = [c for c in candidates(ln)]
        if not cands:
            continue
        probs[j] = {c: float(sp[j, c]) if c < W_MAX else 0.0 for c in cands}
        starts[j] = [c for c in cands if probs[j][c] > 0.5]
    if decoder:
        for j, st in DEC.decode(lines, roles, probs).items():
            starts[j] = st
    return roles, starts, probs


def fit(train_exs, epochs, seed=1, log=print, synth=None, **kw):
    """synth: extra labelled layouts (ml/synth.py) mixed into training only."""
    random.seed(seed)
    torch.manual_seed(seed)
    val = [e for e in train_exs if D.is_val(e)]
    tr = [e for e in train_exs if not D.is_val(e)] + list(synth or [])
    model = GridNet(**kw)
    log(f"  GridNet: {sum(p.numel() for p in model.parameters())} parameters; "
        f"train {len(tr)} docs, validate on {len(val)}")
    train(model, tr, epochs, val, log=log)
    return model


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus-llm.jsonl"))
    ap.add_argument("--epochs", type=int, default=20)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--save", help="write the trained weights here (torch state_dict)")
    a = ap.parse_args(argv)
    torch.set_num_threads(os.cpu_count() or 1)
    model = fit(D.load(a.corpus), a.epochs, a.seed)
    if a.save:
        os.makedirs(os.path.dirname(a.save) or ".", exist_ok=True)
        torch.save(model.state_dict(), a.save)
        print(f"  saved {a.save}")


if __name__ == "__main__":
    main()
