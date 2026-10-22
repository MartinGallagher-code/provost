#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Small neural layout model (PyTorch): one network, both tasks.

The input is the text as a character grid (lines x columns). A stack of 2-D
convolutions looks across and down at once, which is what column alignment
is: a gutter is a vertical stripe of spaces. Two heads read the result:
  * starts: one logit per cell -> does a field start here? (scored at the
    field-start candidates only)
  * roles:  each line's features pooled across its width, then a small
    bidirectional GRU down the lines -> the line's role

About 60k parameters (~120 KB as float16). Needs torch + numpy
(ml/requirements.txt). Usage:

    python3 ml/train_neural.py [--corpus ...] [--synth ...] [--synth-test ...]
        [--epochs 12] [--save ml/models/layoutnet.npz]
"""
import argparse
import functools
import os
import random
import sys
import time

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dataset as D  # noqa: E402
from layout import PREDICTED, candidates, is_blank  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
print = functools.partial(print, flush=True)  # noqa: A001  (progress shows up in a tee'd log)
W_MAX = 240          # columns seen; candidates beyond are scored as misses
H_TRAIN = 64         # lines per training crop
VOCAB = 100


def char_id(ch):
    o = ord(ch)
    if 32 <= o < 127:
        return o - 31          # 1..95
    if ch == "\t":
        return 96
    if 0x2500 <= o <= 0x257F:
        return 97              # box drawing
    if ch.isalpha():
        return 98
    return 99


def encode(ex, lo=0, hi=None, shift=0):
    """Grid + targets for lines lo:hi. shift > 0 indents every line by that
    many spaces (training augmentation: layouts don't depend on indent)."""
    lines = [" " * shift + ln for ln in ex["lines"][lo:hi]]
    H = len(lines)
    W = min(W_MAX, max([len(ln) for ln in lines] + [1]))
    grid = np.zeros((H, W), dtype=np.int64)
    role = np.full(H, -1, dtype=np.int64)
    smask = np.zeros((H, W), dtype=np.float32)   # candidate cells with known labels
    sgold = np.zeros((H, W), dtype=np.float32)
    for h, ln in enumerate(lines):
        for w, ch in enumerate(ln[:W]):
            grid[h, w] = char_id(ch)
        r = ex["roles"][lo + h]
        if r in PREDICTED:
            role[h] = PREDICTED.index(r)
        st = ex["starts"][lo + h]
        if st:
            for c in candidates(ln):
                if c < W:
                    smask[h, c] = 1.0
            for s in st:
                if s + shift < W:
                    sgold[h, s + shift] = 1.0
    return grid, role, smask, sgold


def collate(items):
    H = max(g.shape[0] for g, *_ in items)
    W = max(g.shape[1] for g, *_ in items)
    B = len(items)
    grid = torch.zeros(B, H, W, dtype=torch.long)
    role = torch.full((B, H), -1, dtype=torch.long)
    smask = torch.zeros(B, H, W)
    sgold = torch.zeros(B, H, W)
    for b, (g, r, m, s) in enumerate(items):
        h, w = g.shape
        grid[b, :h, :w] = torch.from_numpy(g)
        role[b, :h] = torch.from_numpy(r)
        smask[b, :h, :w] = torch.from_numpy(m)
        sgold[b, :h, :w] = torch.from_numpy(s)
    return grid, role, smask, sgold


class Block(nn.Module):
    def __init__(self, c, vdil):
        super().__init__()
        self.a = nn.Conv2d(c, c, (3, 3), padding=(vdil, 1), dilation=(vdil, 1))
        self.b = nn.Conv2d(c, c, (1, 5), padding=(0, 4), dilation=(1, 2))

    def forward(self, x):
        return F.relu(x + self.b(F.relu(self.a(x))))


class LayoutNet(nn.Module):
    def __init__(self, c=24, emb=12, hid=32, drop=0.1):
        super().__init__()
        self.drop2d = nn.Dropout2d(drop)
        self.drop = nn.Dropout(2 * drop)
        self.emb = nn.Embedding(VOCAB, emb, padding_idx=0)
        self.inp = nn.Conv2d(emb, c, (3, 3), padding=1)
        self.blocks = nn.Sequential(Block(c, 1), Block(c, 2), Block(c, 4), Block(c, 1))
        self.start = nn.Conv2d(c, 1, 1)
        self.rnn = nn.GRU(2 * c + 1, hid, batch_first=True, bidirectional=True)
        self.role = nn.Linear(2 * hid, len(PREDICTED))

    def forward(self, grid):
        pad = (grid == 0)
        x = self.emb(grid).permute(0, 3, 1, 2)            # B,E,H,W
        x = self.blocks(self.drop2d(F.relu(self.inp(x))))  # B,C,H,W
        starts = self.start(x).squeeze(1)                 # B,H,W
        m = (~pad).unsqueeze(1).float()
        mx = (x * m - (1 - m) * 1e4).amax(3)              # B,C,H
        mean = (x * m).sum(3) / m.sum(3).clamp(min=1)
        blank = (m.sum(3) == 0).float()                   # B,1,H
        rows = torch.cat([mx.clamp(min=-50), mean, blank], 1).permute(0, 2, 1)
        h, _ = self.rnn(self.drop(rows))
        return starts, self.role(self.drop(h))


def batches(examples, bs, train):
    items = []
    for e in examples:
        n = len(e["lines"])
        shift = random.choice([0, 0, 0, 1, 2, 4]) if train else 0
        if train and n > H_TRAIN:
            lo = random.randint(0, n - H_TRAIN)
            items.append(encode(e, lo, lo + H_TRAIN, shift))
        else:
            items.append(encode(e, shift=shift))
    order = sorted(range(len(items)), key=lambda k: items[k][0].size)
    groups = [order[k:k + bs] for k in range(0, len(order), bs)]
    if train:
        random.shuffle(groups)
    for g in groups:
        yield g, collate([items[k] for k in g])


def train(model, examples, epochs, val=None, log=print):
    """AdamW + one-cycle. With val, keep the weights from the epoch that
    scores best on it (line-exact starts + role accuracy)."""
    opt = torch.optim.AdamW(model.parameters(), lr=3e-3, weight_decay=1e-4)
    steps = epochs * ((len(examples) + 15) // 16)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=3e-3, total_steps=steps)
    rw = torch.ones(len(PREDICTED))
    best = (-1.0, 0, None)
    for ep in range(epochs):
        model.train()
        t0, tot, nb = time.time(), 0.0, 0
        for _, (grid, role, smask, sgold) in batches(examples, 16, True):
            s_logit, r_logit = model(grid)
            lr = F.cross_entropy(r_logit.reshape(-1, len(PREDICTED)), role.reshape(-1),
                                 weight=rw, ignore_index=-1)
            ls = (F.binary_cross_entropy_with_logits(s_logit, sgold, reduction="none") * smask).sum() \
                / smask.sum().clamp(min=1)
            loss = lr + ls
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            sched.step()
            tot, nb = tot + loss.item(), nb + 1
        msg = f"    epoch {ep + 1}/{epochs}  loss {tot / max(1, nb):.4f}  ({time.time() - t0:.0f}s)"
        if val:
            rr, br, _ = evaluate(model, val)
            score = rr["acc"] + br["exact"]
            msg += f"  val roles {rr['acc']:.3f} starts {br['exact']:.3f}"
            if score > best[0]:
                best = (score, ep + 1, {k: v.clone() for k, v in model.state_dict().items()})
        log(msg)
    if val:
        model.load_state_dict(best[2])
        log(f"    kept epoch {best[1]} (best on validation)")


@torch.no_grad()
def predict(model, ex):
    model.eval()
    grid, *_ = encode(ex)
    s, r = model(torch.from_numpy(grid).unsqueeze(0))
    roles = r[0].argmax(1).tolist()
    sp = torch.sigmoid(s[0]).numpy()
    starts = []
    for h, ln in enumerate(ex["lines"]):
        starts.append({c for c in candidates(ln) if c < sp.shape[1] and sp[h, c] > 0.5})
    return roles, starts


def evaluate(model, examples):
    gold_r, pred_r, gold_s, pred_s = [], [], [], []
    for e in examples:
        roles, starts = predict(model, e)
        for j, ln in enumerate(e["lines"]):
            if is_blank(ln) or e["roles"][j] not in PREDICTED:
                continue
            gold_r.append(PREDICTED.index(e["roles"][j]))
            pred_r.append(roles[j])
            if e["starts"][j]:
                gold_s.append(set(e["starts"][j]))
                pred_s.append(starts[j])
    return D.role_report(gold_r, pred_r), D.bound_report(gold_s, pred_s), (gold_r, pred_r)


def save_npz(model, path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    np.savez_compressed(path, **{k: v.detach().numpy().astype(np.float16)
                                 for k, v in model.state_dict().items()})


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus.jsonl"))
    ap.add_argument("--synth", default=os.path.join(HERE, "data", "synth.jsonl"))
    ap.add_argument("--synth-test", default=os.path.join(HERE, "data", "synth-test.jsonl"))
    ap.add_argument("--epochs", type=int, default=12)
    ap.add_argument("--synth-share", type=float, default=1.0,
                    help="fraction of the synthetic set mixed into training (0 = corpus only)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--save", help="write the trained weights (float16 .npz) here")
    a = ap.parse_args(argv)
    random.seed(a.seed)
    torch.manual_seed(a.seed)
    torch.set_num_threads(os.cpu_count() or 1)
    ctr, cte = D.split(D.load(a.corpus))
    val = [e for e in ctr if D.is_val(e)]
    ctr = [e for e in ctr if not D.is_val(e)]
    syn = D.load(a.synth)
    syn = syn[: int(len(syn) * a.synth_share)]
    syn_te = D.load(a.synth_test) if os.path.exists(a.synth_test) else []
    model = LayoutNet()
    n = sum(p.numel() for p in model.parameters())
    print(f"LayoutNet: {n} parameters; train {len(ctr)} corpus + {len(syn)} synthetic docs; "
          f"validate on {len(val)} corpus docs (their own families)")
    train(model, ctr + syn, a.epochs, val)
    for tname, te in [("corpus-test", cte)] + ([("synth-test", syn_te)] if syn_te else []):
        rr, br, (g, p) = evaluate(model, te)
        print(f"  {tname:13} roles   " + D.fmt_roles(rr, g, p))
        print(f"  {tname:13} starts  " + D.fmt_bounds(br))
    if a.save:
        save_npz(model, a.save)
        print(f"  saved {a.save} ({os.path.getsize(a.save)} bytes)")


if __name__ == "__main__":
    main()
