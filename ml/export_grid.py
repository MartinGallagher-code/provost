#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Export a trained GridNet (train_grid.py --save) for capture time: float16
weights in extract/model/gridnet.npz, read by extract/model/gridnet.py with
numpy alone. Checks the numpy forward pass against torch on corpus samples.

    python3 ml/export_grid.py ml/models/gridnet.pt [--corpus ml/data/corpus-llm.jsonl]
"""
import argparse
import os
import sys

import numpy as np
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(os.path.dirname(HERE), "extract", "model"))
import dataset as D  # noqa: E402
import gridnet  # noqa: E402
import train_grid as G  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("weights")
    ap.add_argument("--corpus", default=os.path.join(HERE, "data", "corpus-llm.jsonl"))
    ap.add_argument("--out", default=gridnet.WEIGHTS)
    a = ap.parse_args(argv)
    model = G.GridNet()
    model.load_state_dict(torch.load(a.weights))
    model.eval()
    sd = {k: v.detach().numpy().astype(np.float16) for k, v in model.state_dict().items()}
    sd["_heads"] = np.array(model.layers[0].col.num_heads)
    sd["_layers"] = np.array(len(model.layers))
    sd["_line_layers"] = np.array(len(model.lines.layers))
    np.savez_compressed(a.out, **sd)
    print(f"{sum(p.numel() for p in model.parameters())} parameters -> {a.out} "
          f"({os.path.getsize(a.out)} bytes)")
    # the float16 weights must give the same answers as the float32 model
    for v in model.state_dict().values():
        v.copy_(v.half().float())
    net = gridnet.load(a.out)
    worst = 0.0
    for e in D.load(a.corpus)[::150]:
        lines = e["lines"][:G.H_MAX]
        grid = gridnet.encode(lines)
        with torch.no_grad():
            s, r = model(torch.from_numpy(grid).unsqueeze(0))
        s2, r2 = gridnet.forward(net, grid)
        worst = max(worst, float(np.abs(s[0].numpy() - s2).max()), float(np.abs(r[0].numpy() - r2).max()))
    print(f"numpy vs torch, worst logit difference: {worst:.2e}")
    if worst > 1e-3:
        sys.exit("the numpy runtime does not match the trained model")


if __name__ == "__main__":
    main()
