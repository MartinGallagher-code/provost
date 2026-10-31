# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""The tiny-LM layout labeller at capture time (trained by ml/train_lm.py).

    import lm_runtime as LMR
    lm = LMR.load(path)                 # None when torch/transformers/peft or the model is missing
    roles, probs = LMR.run(lm, lines)   # per line: role, {candidate: p} or None

A model directory holds config.json (the base model's name, the LoRA rank)
and weights.pt (the adapter and the two heads). The base model comes from the
Hugging Face cache, downloaded on first use. All of this is optional: the
trees (layout-model.json.gz) need nothing but python3.

The encoding lives here, not in ml/, so training and capture time share it,
as they share layout.py and decode.py: the capture is echoed (capture,
separator, capture again) and the heads read the second copy, so a causal
model sees the rows below a header; each line is cut at its field-start
candidates before tokenizing, so every candidate begins a token.
"""
import json
import os

try:
    import torch
    import torch.nn as nn
except ImportError:  # optional: the trees need none of this
    torch = None
    nn = None

from layout import PREDICTED, candidates, is_blank

BASE = "HuggingFaceTB/SmolLM2-135M"
SEP = "\n=====\n"        # between the two copies
MAX_TOK = 640           # tokens per copy of a window (lines are kept whole)
MAX_LINE = 400          # characters of a line the model sees; later candidates score 0
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
class LMLabeller(nn.Module if nn else object):
    def __init__(self, backbone, hidden):
        super().__init__()
        self.backbone = backbone
        self.start = nn.Sequential(nn.Linear(hidden, hidden), nn.GELU(), nn.Linear(hidden, 1))
        self.role = nn.Sequential(nn.Linear(hidden, hidden), nn.GELU(), nn.Linear(hidden, len(PREDICTED)))

    def forward(self, ids, mask):
        return self.backbone(input_ids=ids, attention_mask=mask).last_hidden_state


def keep_layers(backbone, n):
    """Keep only the first n transformer layers of a Llama-style backbone
    (0, or n >= its layer count, keeps them all). The config's layer count
    moves with them: the forward pass and the cache are sized from it."""
    cfg = backbone.config
    if n and n < cfg.num_hidden_layers:
        backbone.layers = backbone.layers[:n]
        cfg.num_hidden_layers = n
        if getattr(cfg, "layer_types", None):
            cfg.layer_types = cfg.layer_types[:n]
    return backbone


def build(base=BASE, lora=16, full=False, backbone=None, checkpointing=False, layers=0):
    """(model, tokenizer). backbone: an already-built transformers model
    (tests). checkpointing trades ~30% more time for much less memory;
    layers: keep only the base's first N transformer layers (0 = all)."""
    tok = None
    if backbone is None:
        from transformers import AutoModel, AutoTokenizer
        tok = AutoTokenizer.from_pretrained(base)
        backbone = AutoModel.from_pretrained(base, dtype=torch.float32, attn_implementation="sdpa")
    keep_layers(backbone, layers)
    if checkpointing:
        backbone.gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})
        backbone.enable_input_require_grads()
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


def available():
    """True when torch, transformers and peft can be imported."""
    if torch is None:
        return False
    try:
        import peft  # noqa: F401
        import transformers  # noqa: F401
    except ImportError:
        return False
    return True


def load_model(path):
    """(model, encoder) from a train_lm.py --save directory; raises if it can't."""
    with open(os.path.join(path, "config.json"), encoding="utf-8") as fh:
        cfg = json.load(fh)
    model, tok = build(cfg.get("base", BASE), cfg.get("lora", 16), cfg.get("full", False),
                       layers=cfg.get("layers", 0))
    model.load_state_dict(torch.load(os.path.join(path, "weights.pt"), map_location="cpu"), strict=False)
    model.meta = cfg
    model.eval()
    return model, hf_encoder(tok, cfg.get("max_tok", MAX_TOK))


def load(path):
    """load_model, or None when the runtime or the model is missing."""
    if not path or not os.path.isfile(os.path.join(path, "weights.pt")) or not available():
        return None
    try:
        return load_model(path)
    except Exception:  # noqa: BLE001 -- a broken or unfetchable model declines, like a missing one
        return None


def run(lm, lines):
    """(roles, probs): a role per line ("blank" by rule) and, per line with
    field-start candidates, {candidate offset: p} (0.0 past MAX_LINE)."""
    model, enc = lm
    model.eval()
    dev = next(model.parameters()).device
    roles = ["blank" if is_blank(ln) else None for ln in lines]
    probs = [None] * len(lines)
    for j, ln in enumerate(lines):
        cs = candidates(ln)
        if cs:
            probs[j] = {c: 0.0 for c in cs}
    with torch.no_grad():
        for it in items(enc, {"lines": lines}, with_targets=False):
            ids, mask = collate([it])
            h = model(ids.to(dev), mask.to(dev))[0]
            if it["cpos"]:
                p = torch.sigmoid(model.start(h[torch.tensor(it["cpos"], device=dev)]).squeeze(-1)).tolist()
                for (j, c), q in zip(it["cref"], p):
                    probs[j][c] = float(q)
            if it["rpos"]:
                r = model.role(h[torch.tensor(it["rpos"], device=dev)]).argmax(-1).tolist()
                for j, k in zip(it["rref"], r):
                    roles[j] = PREDICTED[k]
    return [r or "skip" for r in roles], probs
