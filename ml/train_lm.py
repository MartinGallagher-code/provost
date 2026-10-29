#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""A tiny pretrained language model as the layout labeller (PyTorch +
transformers + peft; a CPU is enough for the 135M model).

The trees and GridNet learn layout from scratch on ~3,700 captures and stop
at about 83% of the LLM teacher's splits on unseen families: they are
data-bound. A pretrained model already knows what words, numbers, dates and
units look like; this fine-tunes one (SmolLM2-135M by default) to give the
same two answers they do, so the decoder, the scoring and provost's runtime
can stay as they are:
  * starts: for every field-start candidate (layout.candidates), is it one?
  * roles: header / row / cont / kv / section / skip for every line.

"Echo" labelling: a causal model only sees what came before a token, and a
header can only be told from the rows below it. So the text is the capture,
a separator, then the capture again, and the heads read the SECOND copy,
whose every token has seen the whole capture. Each line is cut at its
candidates before tokenizing, so every candidate begins a token of its own
and offsets map to tokens exactly. One forward pass, nothing generated.

Training is LoRA on every linear layer of the backbone plus the two small
heads (--full fine-tunes everything); the saved model is the adapter and the
heads, ~10 MB, plus the name of the base model to fetch from Hugging Face.

    python3 ml/train_lm.py --corpus ml/data/corpus-llm.jsonl --save ml/models/lm
    python3 ml/fold_eval.py --learner lm --lm-load ml/models/lm
"""
import argparse
import functools
import json
import math
import os
import random
import sys
import time

import torch
import torch.nn as nn
import torch.nn.functional as F

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extract", "model"))
import dataset as D  # noqa: E402
import decode as DEC  # noqa: E402
from layout import PREDICTED, candidates, is_blank  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
print = functools.partial(print, flush=True)  # noqa: A001
BASE = "HuggingFaceTB/SmolLM2-135M"
SEP = "\n=====\n"        # between the two copies
MAX_TOK = 640           # tokens per copy of a window (lines are kept whole)
MAX_LINE = 400          # characters of a line the model sees; later candidates score 0
BATCH_TOK = 6000        # padded tokens per training batch
LORA_TARGETS = ["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]


# -- encoding ----------------------------------------------------------------
def pieces(line):
    """The line cut at each field-start candidate: [(offset or None, text)].
    The leading run before the first candidate (indentation) has no offset."""
    line = line[:MAX_LINE]
    cs = candidates(line)
    out = []
    if not cs:
        return [(None, line)] if line else []
    if cs[0] > 0:
        out.append((None, line[:cs[0]]))
    for k, c in enumerate(cs):
        e = cs[k + 1] if k + 1 < len(cs) else len(line)
        out.append((c, line[c:e]))
    return out


class Encoder:
    """Turns lines into echo sequences. tokenize(list of str) -> list of id
    lists, without special tokens; bos is prepended when not None."""

    def __init__(self, tokenize, bos=None, max_tok=MAX_TOK):
        self.tokenize, self.bos, self.max_tok = tokenize, bos, max_tok
        self.nl = tokenize(["\n"])[0]
        self.sep = tokenize([SEP])[0]

    def lines(self, lines):
        """Per line: (ids, [(candidate offset, index of its first token)])."""
        out = []
        for ln in lines:
            ps = pieces(ln)
            toks = self.tokenize([t for _, t in ps]) if ps else []
            ids, cand = [], []
            for (c, _), t in zip(ps, toks):
                if c is not None and t:
                    cand.append((c, len(ids)))
                ids.extend(t)
            out.append((ids, cand))
        return out

    def windows(self, lines):
        """Line ranges (lo, hi) whose copy fits max_tok (a longer single line
        is cut at the budget), and the per-line encodings."""
        enc = self.lines(lines)
        wins, lo, size = [], 0, 0
        for j, (ids, _) in enumerate(enc):
            n = len(ids) + len(self.nl)
            if j > lo and size + n > self.max_tok:
                wins.append((lo, j))
                lo, size = j, 0
            size += n
        if lo < len(enc) or not enc:
            wins.append((lo, len(enc)))
        return enc, wins

    def sequence(self, enc, lo, hi):
        """ids, and for each line in [lo, hi): the position of its last token
        in the second copy (the newline) and its candidates' positions there."""
        body, where = [], []
        for j in range(lo, hi):
            ids, cand = enc[j]
            ids = ids[: self.max_tok]
            start = len(body)
            body.extend(ids)
            body.extend(self.nl)
            where.append((start, [(c, start + p) for c, p in cand if p < len(ids)], len(body) - 1))
        head = ([self.bos] if self.bos is not None else []) + body + self.sep
        off = len(head)
        seq = head + body
        pos = [(lo + i, [(c, off + p) for c, p in cs], off + e) for i, (_, cs, e) in enumerate(where)]
        return seq, pos


def items(enc_obj, ex, with_targets=True):
    """Training/prediction items for one document: one per window."""
    lines = ex["lines"]
    enc, wins = enc_obj.windows(lines)
    out = []
    for lo, hi in wins:
        seq, pos = enc_obj.sequence(enc, lo, hi)
        cpos, cgold, rpos, rgold, cref, rref = [], [], [], [], [], []
        for j, cs, e in pos:
            if is_blank(lines[j]):
                continue
            rref.append(j)
            rpos.append(e)
            if with_targets:
                r = ex["roles"][j]
                rgold.append(PREDICTED.index(r) if r in PREDICTED else -100)
            st = ex["starts"][j] if with_targets else None
            for c, p in cs:
                cref.append((j, c))
                cpos.append(p)
                if with_targets:
                    cgold.append(-1.0 if st is None else (1.0 if c in st else 0.0))
        out.append({"ids": seq, "cpos": cpos, "cgold": cgold, "rpos": rpos, "rgold": rgold,
                    "cref": cref, "rref": rref})
    return out


# -- the model -------------------------------------------------------------------
class LMLabeller(nn.Module):
    def __init__(self, backbone, hidden):
        super().__init__()
        self.backbone = backbone
        self.start = nn.Sequential(nn.Linear(hidden, hidden), nn.GELU(), nn.Linear(hidden, 1))
        self.role = nn.Sequential(nn.Linear(hidden, hidden), nn.GELU(), nn.Linear(hidden, len(PREDICTED)))

    def forward(self, ids, mask):
        return self.backbone(input_ids=ids, attention_mask=mask).last_hidden_state


def build(base=BASE, lora=16, full=False, backbone=None):
    """(model, encoder). backbone: an already-built transformers model (tests)."""
    tok = None
    if backbone is None:
        from transformers import AutoModel, AutoTokenizer
        tok = AutoTokenizer.from_pretrained(base)
        backbone = AutoModel.from_pretrained(base, torch_dtype=torch.float32)
    if not full and lora:
        from peft import LoraConfig, get_peft_model
        backbone = get_peft_model(backbone, LoraConfig(r=lora, lora_alpha=2 * lora, lora_dropout=0.05,
                                                       target_modules=LORA_TARGETS, bias="none"))
    model = LMLabeller(backbone, backbone.config.hidden_size)
    return model, tok


def hf_encoder(tok, max_tok=MAX_TOK):
    return Encoder(lambda xs: tok(list(xs), add_special_tokens=False)["input_ids"], tok.bos_token_id, max_tok)


def collate(batch, pad=0):
    n = max(len(b["ids"]) for b in batch)
    ids = torch.full((len(batch), n), pad, dtype=torch.long)
    mask = torch.zeros((len(batch), n), dtype=torch.long)
    for i, b in enumerate(batch):
        ids[i, : len(b["ids"])] = torch.tensor(b["ids"])
        mask[i, : len(b["ids"])] = 1
    return ids, mask


def batches(all_items, shuffle, budget=BATCH_TOK):
    """Length-sorted buckets of at most `budget` padded tokens."""
    order = sorted(range(len(all_items)), key=lambda i: len(all_items[i]["ids"]))
    groups, cur, longest = [], [], 0
    for i in order:
        n = len(all_items[i]["ids"])
        if cur and max(longest, n) * (len(cur) + 1) > budget:
            groups.append(cur)
            cur, longest = [], 0
        cur.append(i)
        longest = max(longest, n)
    if cur:
        groups.append(cur)
    if shuffle:
        random.shuffle(groups)
    for g in groups:
        yield [all_items[i] for i in g]


def loss_of(model, batch):
    ids, mask = collate(batch)
    h = model(ids, mask)
    ls, lr, ns, nr = h.new_zeros(()), h.new_zeros(()), 0, 0
    bi, ci, cg, ri, rp, rg = [], [], [], [], [], []
    for i, b in enumerate(batch):
        for p, g in zip(b["cpos"], b["cgold"]):
            if g >= 0:
                bi.append(i)
                ci.append(p)
                cg.append(g)
        for p, g in zip(b["rpos"], b["rgold"]):
            if g >= 0:
                ri.append(i)
                rp.append(p)
                rg.append(g)
    if ci:
        logit = model.start(h[torch.tensor(bi), torch.tensor(ci)]).squeeze(-1)
        ls = F.binary_cross_entropy_with_logits(logit, torch.tensor(cg))
        ns = len(ci)
    if rp:
        logit = model.role(h[torch.tensor(ri), torch.tensor(rp)])
        lr = F.cross_entropy(logit, torch.tensor(rg))
        nr = len(rp)
    return ls + lr, ns, nr


def trainable(model):
    return [p for p in model.parameters() if p.requires_grad]


@torch.no_grad()
def val_loss(model, val_items):
    model.eval()
    tot, k = 0.0, 0
    for b in batches(val_items, False):
        tot += loss_of(model, b)[0].item()
        k += 1
    return tot / max(1, k)


def train(model, tr_items, epochs, val_items=None, lr=3e-4, head_lr=1e-3, log=print,
          ckpt=None, ckpt_every=0, budget=BATCH_TOK):
    """AdamW, linear warm-up then cosine; with val, keep the lowest val loss."""
    heads = [p for n, p in model.named_parameters() if not n.startswith("backbone.") and p.requires_grad]
    body = [p for n, p in model.named_parameters() if n.startswith("backbone.") and p.requires_grad]
    opt = torch.optim.AdamW([{"params": body, "lr": lr}, {"params": heads, "lr": head_lr}], weight_decay=0.01)
    nb = sum(1 for _ in batches(tr_items, False, budget))
    total = max(1, epochs * nb)
    warm = max(1, total // 20)
    sched = torch.optim.lr_scheduler.LambdaLR(
        opt, lambda s: min(1.0, (s + 1) / warm) * 0.5 * (1 + math.cos(math.pi * min(1.0, s / total))))
    best, step, t0 = (float("inf"), 0, None), 0, time.time()
    for ep in range(epochs):
        model.train()
        te, tot, k, toks = time.time(), 0.0, 0, 0
        for b in batches(tr_items, True, budget):
            loss, _, _ = loss_of(model, b)
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(trainable(model), 1.0)
            opt.step()
            sched.step()
            step += 1
            tot, k = tot + loss.item(), k + 1
            toks += sum(len(x["ids"]) for x in b)
            if step % 20 == 0:
                log(f"    step {step}/{total}  loss {tot / k:.4f}  {toks / (time.time() - te):.0f} tok/s"
                    f"  ({(time.time() - t0) / 60:.1f} min)")
            if ckpt and ckpt_every and step % ckpt_every == 0:
                save(model, os.path.join(ckpt, "last"))
        msg = f"    epoch {ep + 1}/{epochs}  loss {tot / max(1, k):.4f}  ({time.time() - te:.0f}s)"
        if val_items:
            v = val_loss(model, val_items)
            msg += f"  val {v:.4f}"
            if v < best[0]:
                best = (v, ep + 1, {n: t.detach().clone() for n, t in model.state_dict().items()
                                    if n in _trainable_names(model)})
                if ckpt:
                    save(model, os.path.join(ckpt, "best"))
        if ckpt:
            save(model, os.path.join(ckpt, "last"))
        log(msg)
    if val_items and best[2] is not None:
        model.load_state_dict(best[2], strict=False)
        log(f"    kept epoch {best[1]} (lowest validation loss)")


def _trainable_names(model):
    return {n for n, p in model.named_parameters() if p.requires_grad}


# -- saving ------------------------------------------------------------------------
def save(model, path, meta=None):
    """The trainable weights only (LoRA adapter + heads) and how to rebuild."""
    os.makedirs(path, exist_ok=True)
    names = _trainable_names(model)
    torch.save({n: t.detach().cpu() for n, t in model.state_dict().items() if n in names},
               os.path.join(path, "weights.pt"))
    cfg = dict(getattr(model, "meta", {}), **(meta or {}))
    with open(os.path.join(path, "config.json"), "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=1)


def load(path):
    with open(os.path.join(path, "config.json"), encoding="utf-8") as fh:
        cfg = json.load(fh)
    model, tok = build(cfg.get("base", BASE), cfg.get("lora", 16), cfg.get("full", False))
    model.load_state_dict(torch.load(os.path.join(path, "weights.pt")), strict=False)
    model.meta = cfg
    model.eval()
    return model, hf_encoder(tok, cfg.get("max_tok", MAX_TOK))


# -- prediction ----------------------------------------------------------------------
@torch.no_grad()
def predict_doc(model, enc, ex, decoder=False):
    """(roles, starts, probs) like crossval.predict_doc: probs is per line
    {candidate offset: p}, None for a line without candidates."""
    model.eval()
    lines = ex["lines"]
    roles = ["blank" if is_blank(ln) else None for ln in lines]
    probs = [None] * len(lines)
    for j, ln in enumerate(lines):
        cs = candidates(ln)
        if cs:
            probs[j] = {c: 0.0 for c in cs}
    for it in items(enc, ex, with_targets=False):
        ids, mask = collate([it])
        h = model(ids, mask)[0]
        if it["cpos"]:
            p = torch.sigmoid(model.start(h[torch.tensor(it["cpos"])]).squeeze(-1)).tolist()
            for (j, c), q in zip(it["cref"], p):
                probs[j][c] = float(q)
        if it["rpos"]:
            r = model.role(h[torch.tensor(it["rpos"])]).argmax(-1).tolist()
            for j, k in zip(it["rref"], r):
                roles[j] = PREDICTED[k]
    for j in range(len(lines)):
        if roles[j] is None:
            roles[j] = "skip"
    starts = [None if p is None else [c for c, q in p.items() if q > 0.5] for p in probs]
    if decoder:
        for j, st in DEC.decode(lines, roles, probs).items():
            starts[j] = st
    return roles, starts, probs


def fit(train_exs, epochs, base=BASE, lora=16, full=False, seed=1, log=print, extra=None,
        ckpt=None, ckpt_every=0, max_tok=MAX_TOK, lr=3e-4):
    """Train on train_exs (+ extra layouts), validating on their val families."""
    random.seed(seed)
    torch.manual_seed(seed)
    model, tok = build(base, lora, full)
    model.meta = {"base": base, "lora": lora, "full": full, "max_tok": max_tok}
    enc = hf_encoder(tok, max_tok)
    val = [e for e in train_exs if D.is_val(e)]
    tr = [e for e in train_exs if not D.is_val(e)] + list(extra or [])
    t0 = time.time()
    tr_items = [i for e in tr for i in items(enc, e)]
    val_items = [i for e in val for i in items(enc, e)]
    nall = sum(p.numel() for p in model.parameters())
    ntr = sum(p.numel() for p in trainable(model))
    log(f"  {base}: {nall / 1e6:.1f}M parameters, {ntr / 1e6:.2f}M trained; "
        f"{len(tr)} docs ({len(tr_items)} windows, {sum(len(i['ids']) for i in tr_items)} tokens), "
        f"validate on {len(val)}; encoded in {time.time() - t0:.0f}s")
    train(model, tr_items, epochs, val_items, lr=lr, log=log, ckpt=ckpt, ckpt_every=ckpt_every)
    return model, enc


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus-llm.jsonl"))
    ap.add_argument("--extra", nargs="*", default=[], help="extra training sets (family-free layouts)")
    ap.add_argument("--fold", type=int, default=None, help="train on every crossval fold but this one")
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--lora", type=int, default=16, help="LoRA rank (0 with --full)")
    ap.add_argument("--full", action="store_true", help="fine-tune every weight, not a LoRA adapter")
    ap.add_argument("--epochs", type=int, default=2)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--max-docs", type=int, default=0, help="train on a random sample (a pilot)")
    ap.add_argument("--max-tok", type=int, default=MAX_TOK)
    ap.add_argument("--threads", type=int, default=os.cpu_count() or 1)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--save", help="write the adapter + heads here (with last/ and best/ checkpoints)")
    ap.add_argument("--ckpt-every", type=int, default=200, help="steps between checkpoints in --save/last")
    a = ap.parse_args(argv)
    torch.set_num_threads(a.threads)
    exs = D.load(a.corpus)
    if a.fold is not None:
        import crossval as CV
        exs = [e for e in exs if CV.fold(e) != a.fold]
    if a.max_docs:
        random.Random(a.seed).shuffle(exs)
        exs = exs[: a.max_docs]
    extra = [e for p in a.extra for e in D.load(p)]
    model, _ = fit(exs, a.epochs, a.base, a.lora, a.full, a.seed, extra=extra,
                   ckpt=a.save, ckpt_every=a.ckpt_every if a.save else 0, max_tok=a.max_tok, lr=a.lr)
    if a.save:
        save(model, a.save, {"fold": a.fold, "epochs": a.epochs, "docs": len(exs), "extra": a.extra})
        print(f"saved -> {a.save}")


if __name__ == "__main__":
    main()
