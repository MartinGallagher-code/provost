# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""The tiny-LM layout labeller at capture time (trained by ml/train_lm.py).

    import lm_runtime as LMR
    lm = LMR.load(path)                 # None when torch/transformers/peft or the model is missing
    roles, probs = LMR.run(lm, lines)   # per line: role, {candidate: p} or None

A model directory is one of two kinds:
- what ml/train_lm.py saves: config.json (the base model's name, the LoRA
  rank) and weights.pt (the adapter and the two heads). It needs torch,
  transformers and peft, and the base model comes from the Hugging Face
  cache, downloaded on first use.
- what ml/export_lm.py writes from one: the whole model at 8 bits, run by
  lm_numpy.py on numpy alone. load and run hand those over to it.
All of this is optional: the trees (layout-model.json.gz) need nothing but
python3.

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
from lm_encode import (MAX_LINE, MAX_TOK, NUMPY_FORMAT, SEP, Encoder,  # noqa: F401  (re-exported)
                        is_numpy_dir, items, pieces)

BASE = "HuggingFaceTB/SmolLM2-135M"
LORA_TARGETS = ["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]


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
    """(model, encoder) from a train_lm.py --save directory, or an
    export_lm.py one (numpy); raises if it can't."""
    with open(os.path.join(path, "config.json"), encoding="utf-8") as fh:
        cfg = json.load(fh)
    if is_numpy_dir(path):
        import lm_numpy
        return lm_numpy.load(path)
    model, tok = build(cfg.get("base", BASE), cfg.get("lora", 16), cfg.get("full", False),
                       layers=cfg.get("layers", 0))
    model.load_state_dict(torch.load(os.path.join(path, "weights.pt"), map_location="cpu"), strict=False)
    model.meta = cfg
    model.eval()
    return model, hf_encoder(tok, cfg.get("max_tok", MAX_TOK))


def load(path):
    """load_model, or None when the runtime or the model is missing."""
    if not path:
        return None
    if not is_numpy_dir(path) and (not os.path.isfile(os.path.join(path, "weights.pt")) or not available()):
        return None
    try:
        return load_model(path)
    except Exception:  # noqa: BLE001 -- a broken or unfetchable model declines, like a missing one
        return None


def run(lm, lines):
    """(roles, probs): a role per line ("blank" by rule) and, per line with
    field-start candidates, {candidate offset: p} (0.0 past MAX_LINE)."""
    model, enc = lm
    if getattr(model, "numpy", False):
        import lm_numpy
        return lm_numpy.run(lm, lines)
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
