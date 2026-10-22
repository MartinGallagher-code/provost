#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Compile the trained boosters into the runtime model file.

LightGBM's text dumps are turned into nested lists that plain Python walks
(extract/model/layout_model.py): a split is [feature, threshold, left,
right], a leaf is a number. Every split here is numeric `<=` and no feature
is ever missing, so that is all the evaluator needs; this script refuses
anything else rather than export a model the runtime would misread.

    python3 ml/export_model.py --roles ml/models/baseline-final-roles.txt \\
        --starts ml/models/baseline-final-starts.txt \\
        [-o extract/model/layout-model.json.gz]
"""
import argparse
import datetime
import gzip
import json
import os
import sys

import lightgbm as lgb

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extract", "model"))
from layout import PREDICTED  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _compile(node):
    if "leaf_value" in node:
        return float(f"{node['leaf_value']:.7g}")
    if node.get("decision_type", "<=") != "<=":
        raise SystemExit(f"unsupported split {node.get('decision_type')}")
    return [node["split_feature"], float(node["threshold"]),
            _compile(node["left_child"]), _compile(node["right_child"])]


def compile_booster(path):
    d = lgb.Booster(model_file=path).dump_model()
    return {"num_class": d.get("num_class", 1), "num_features": d["max_feature_idx"] + 1,
            "trees": [_compile(t["tree_structure"]) for t in d["tree_info"]]}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--roles", required=True)
    ap.add_argument("--starts", required=True)
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "extract", "model", "layout-model.json.gz"))
    ap.add_argument("--note", default="trees on new features + --clean 0.05 --fix-labels, whole corpus")
    a = ap.parse_args(argv)
    model = {"format": 1, "created": datetime.date.today().isoformat(), "note": a.note,
             "classes": PREDICTED, "roles": compile_booster(a.roles), "starts": compile_booster(a.starts)}
    raw = json.dumps(model, separators=(",", ":")).encode()
    with gzip.GzipFile(a.out, "wb", mtime=0) as fh:   # mtime=0: same model, same bytes
        fh.write(raw)
    print(f"wrote {a.out}: {len(model['roles']['trees'])} role trees, "
          f"{len(model['starts']['trees'])} start trees, {os.path.getsize(a.out)} bytes", file=sys.stderr)


if __name__ == "__main__":
    main()
