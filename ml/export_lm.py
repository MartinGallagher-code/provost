# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Export a trained tiny LM (ml/train_lm.py --save DIR) for the numpy runtime
(extract/model/lm_numpy.py), so capture time needs numpy and nothing else.

    python3 ml/export_lm.py --model ml/models/lm-all-l18 --out ml/models/np-l18
    python3 ml/export_lm.py --model DIR --out OUT --check 200   # and compare with torch

The LoRA adapter is merged into the base model's weights; only the layers the
model kept are written. Each linear layer and the vocabulary table are stored
at 8 bits, one scale per row; the norms and the two heads stay float.
--embed 4 stores the vocabulary table at 4 bits (one scale per row and group
of 64 columns), 13 MB smaller at 18 layers, but it moves the model further
from torch: on round 4, 65 of 107 whole-capture outputs stay identical
against 84 at 8 bits.
Shards (weights-N.npz) are cut under --shard-mb. tokenizer.json is the
tokenizer as transformers loads it, which extract/model/bpe.py reads.

--arbiter FILE copies an ml/arbiter.py fit into the export as arbiter.json,
so the model carries its own arbiter (extract/model/arbitrate.load_for_lm
uses it before provost's own arbiter-lm.json). Fit it for this model:
out-of-fold predictions of the same recipe (PV-012).

--check N runs the first N corpus captures through both runtimes and reports
how often their decisions agree, and checks the tokenizer on every piece of
the corpus. Needs torch, transformers and peft (dev-only).
"""
import argparse
import json
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(os.path.dirname(HERE), "extract", "model"))
import dataset as D  # noqa: E402
import lm_numpy as LMN  # noqa: E402
import lm_runtime as LMR  # noqa: E402
from layout import PREDICTED  # noqa: E402

PROJ = {"q": "self_attn.q_proj", "k": "self_attn.k_proj", "v": "self_attn.v_proj", "o": "self_attn.o_proj",
        "gate": "mlp.gate_proj", "up": "mlp.up_proj", "down": "mlp.down_proj"}


def quant8(w):
    """(int8 rows, float16 scales): symmetric, one scale per row."""
    s = np.abs(w).max(axis=1) / 127.0
    s[s == 0] = 1.0
    return np.clip(np.rint(w / s[:, None]), -127, 127).astype(np.int8), s.astype(np.float16)


def quant4(w, group=64):
    """(uint8 packed, float16 scales): symmetric 4 bits, one scale per row
    and group of columns; two values a byte, low nibble first, offset 8."""
    rows, cols = w.shape
    g = w.reshape(rows, cols // group, group)
    s = np.abs(g).max(axis=2) / 7.0
    s[s == 0] = 1.0
    q = (np.clip(np.rint(g / s[:, :, None]), -7, 7).astype(np.int8) + 8).astype(np.uint8).reshape(rows, cols)
    return (q[:, 0::2] | (q[:, 1::2] << 4)).astype(np.uint8), s.astype(np.float16)


def tensors(model, quant, embed_bits):
    """{name: array} in lm_numpy's layout, from a merged LMLabeller."""
    sd = {k: v.detach().cpu().float().numpy() for k, v in model.backbone.state_dict().items()}
    out = {}
    emb = sd["embed_tokens.weight"]
    if quant == "fp32":
        out["embed.w"] = emb
    elif embed_bits == 8:
        out["embed.q"], out["embed.s"] = quant8(emb)
    else:
        out["embed.q"], out["embed.s"] = quant4(emb)
    n = model.backbone.config.num_hidden_layers
    for i in range(n):
        p = f"layers.{i}."
        out[f"l{i}.in_norm"] = sd[p + "input_layernorm.weight"]
        out[f"l{i}.post_norm"] = sd[p + "post_attention_layernorm.weight"]
        for k, name in PROJ.items():
            w = sd[p + name + ".weight"]
            if quant == "fp32":
                out[f"l{i}.{k}.w"] = w
            else:
                out[f"l{i}.{k}.q"], out[f"l{i}.{k}.s"] = quant8(w)
    out["norm"] = sd["norm.weight"]
    for head in ("start", "role"):
        seq = getattr(model, head)
        out[f"{head}.w0"], out[f"{head}.b0"] = seq[0].weight.detach().numpy(), seq[0].bias.detach().numpy()
        out[f"{head}.w1"], out[f"{head}.b1"] = seq[2].weight.detach().numpy(), seq[2].bias.detach().numpy()
    return out


def write(out_dir, ts, cfg, tok_json, shard_mb):
    """Shards in the order the names came, each under shard_mb."""
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.startswith("weights-") and f.endswith(".npz"):
            os.remove(os.path.join(out_dir, f))
    shards, cur, size = [], {}, 0
    for k, v in ts.items():
        if cur and size + v.nbytes > shard_mb * 1e6:
            shards.append(cur)
            cur, size = {}, 0
        cur[k] = v
        size += v.nbytes
    if cur:
        shards.append(cur)
    names = []
    for i, sh in enumerate(shards, 1):
        names.append(f"weights-{i}.npz")
        np.savez(os.path.join(out_dir, names[-1]), **sh)
    cfg = dict(cfg, shards=names)
    with open(os.path.join(out_dir, "config.json"), "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=1)
    with open(os.path.join(out_dir, "tokenizer.json"), "w", encoding="utf-8") as fh:
        fh.write(tok_json)
    return names


def export(model_dir, out_dir, quant="int8", embed_bits=8, shard_mb=45):
    from transformers import AutoTokenizer
    model, _ = LMR.load_model(model_dir)
    meta = dict(model.meta)
    if hasattr(model.backbone, "merge_and_unload"):
        model.backbone = model.backbone.merge_and_unload()
    c = model.backbone.config
    cfg = {"format": LMN.FORMAT, "hidden": c.hidden_size, "layers": c.num_hidden_layers,
           "heads": c.num_attention_heads, "kv_heads": c.num_key_value_heads,
           "head_dim": c.hidden_size // c.num_attention_heads, "intermediate": c.intermediate_size,
           "rope_theta": c.rope_parameters["rope_theta"] if getattr(c, "rope_parameters", None) else c.rope_theta,
           "rms_eps": c.rms_norm_eps, "vocab": c.vocab_size,
           "quant": quant if quant == "fp32" else f"int8, vocabulary table int{embed_bits}",
           "roles": PREDICTED, "max_tok": meta.get("max_tok", LMR.MAX_TOK),
           "source": {k: meta.get(k) for k in ("base", "lora", "layers", "fold", "epochs", "docs", "no_val")}}
    tok = AutoTokenizer.from_pretrained(meta.get("base", LMR.BASE))
    cfg["bos"] = tok.bos_token_id
    names = write(out_dir, tensors(model, quant, embed_bits), cfg, tok.backend_tokenizer.to_str(), shard_mb)
    return model, tok, names


def check(model, tok, out_dir, n):
    """Decisions of the torch model and the export, on the first n captures."""
    import torch
    lm_t = (model.eval(), LMR.hf_encoder(tok, model.meta.get("max_tok", LMR.MAX_TOK)))
    t0 = time.time()
    lm_n = LMN.load(out_dir)
    print(f"  numpy model loaded in {time.time() - t0:.1f}s")
    exs = D.load(os.path.join(HERE, "data", "corpus-llm.jsonl"))[:n]
    texts = sorted({t for ex in exs for ln in ex["lines"] for _, t in LMR.pieces(ln)} | {"\n", LMR.SEP})
    want = tok(texts, add_special_tokens=False)["input_ids"]
    bad = sum(w != g for w, g in zip(want, lm_n[1].tokenize(texts)))
    print(f"  tokenizer: {len(texts)} pieces, {bad} differ")
    roles = same_r = starts = same_s = 0
    worst, tt, tn = 0.0, 0.0, 0.0
    for ex in exs:
        a = time.time()
        with torch.no_grad():
            rt, pt = LMR.run(lm_t, ex["lines"])
        b = time.time()
        rn, pn = LMN.run(lm_n, ex["lines"])
        tt, tn = tt + b - a, tn + time.time() - b
        roles += len(rt)
        same_r += sum(x == y for x, y in zip(rt, rn))
        for x, y in zip(pt, pn):
            for c in (x or {}):
                starts += 1
                same_s += (x[c] > 0.5) == (y[c] > 0.5)
                worst = max(worst, abs(x[c] - y[c]))
    print(f"  {len(exs)} captures: roles agree {same_r}/{roles}, starts agree {same_s}/{starts}, "
          f"largest probability gap {worst:.4f}; torch {tt:.1f}s, numpy {tn:.1f}s")


def write_arbiter(src, out_dir):
    """src's coefficients as out_dir/arbiter.json; its "model" fingerprint is
    dropped, since a file inside the model's directory belongs to that model."""
    with open(src, encoding="utf-8") as fh:
        m = json.load(fh)
    if not isinstance(m.get("coef"), list) or "intercept" not in m:
        raise SystemExit(f"{src}: not an ml/arbiter.py --save file")
    m.pop("model", None)
    with open(os.path.join(out_dir, "arbiter.json"), "w", encoding="utf-8") as fh:
        json.dump(m, fh, indent=1)
        fh.write("\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--model", required=True, help="a train_lm.py --save directory")
    ap.add_argument("--out", required=True)
    ap.add_argument("--quant", choices=["int8", "fp32"], default="int8")
    ap.add_argument("--embed", type=int, choices=[4, 8], default=8, help="bits for the vocabulary table")
    ap.add_argument("--shard-mb", type=float, default=45)
    ap.add_argument("--check", type=int, default=0, metavar="N", help="compare with torch on N captures")
    ap.add_argument("--arbiter", help="an ml/arbiter.py --save file to ship in the export as arbiter.json")
    a = ap.parse_args(argv)
    model, tok, names = export(a.model, a.out, a.quant, a.embed, a.shard_mb)
    if a.arbiter:
        write_arbiter(a.arbiter, a.out)
    total = sum(os.path.getsize(os.path.join(a.out, f)) for f in names)
    print(f"wrote {a.out}: {len(names)} shard(s), {total / 1e6:.1f} MB of weights")
    if a.check:
        check(model, tok, a.out, a.check)


if __name__ == "__main__":
    main()
