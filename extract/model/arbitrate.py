# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""The arbiter at capture time: on a line where the engine's field split and
the model's differ, keep the one a small logistic regression trusts more.

Its inputs per line: each split's log-likelihood under the model's own
per-candidate probabilities, both field counts, how often neighbouring lines
share each split's count, and the engine's confidence / line coverage /
column consistency for the capture. ml/arbiter.py fits it on out-of-fold
predictions (lines where exactly one of the two is right) and writes the
coefficients; this module only applies them. Stdlib only.

Each labeller has its own, since the inputs are that labeller's
probabilities:
  * arbiter.json: the shipped trees';
  * the tiny LM's: arbiter.json in the LM's own model directory when it
    ships one, else arbiter-lm.json here, which records the fingerprint of
    the model it was fitted for (fingerprint()) and applies to that model
    only. Any other LM gets no arbiter, as before PV-012.
"""
import hashlib
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
COEFFS = os.path.join(HERE, "arbiter.json")
LM_COEFFS = os.path.join(HERE, "arbiter-lm.json")


def loglik(probs, split):
    """probs: [(position, p)] for a line's candidates."""
    s, out = set(split), 0.0
    for x, p in probs:
        p = min(max(p, 1e-4), 1 - 1e-4)
        out += math.log(p if x in s else 1 - p)
    return out


def _consistency(starts, j):
    me = len(starts[j])
    nb = [k for k in range(max(0, j - 3), min(len(starts), j + 4)) if k != j and starts[k]]
    if not nb:
        return -1.0
    return sum(1 for k in nb if len(starts[k]) == me) / len(nb)


def features(eng_starts, mod_starts, probs, j, meta, strategy, role):
    """eng_starts / mod_starts: per line (lists or None); probs: per line
    [(pos, p)]; meta: [confidence, coverage, consistency] (-1 = unknown)."""
    pr = probs[j] or []
    le, lm = loglik(pr, eng_starts[j]), loglik(pr, mod_starts[j])
    return [le - lm, le, lm, len(eng_starts[j]), len(mod_starts[j]),
            len(eng_starts[j]) - len(mod_starts[j]),
            _consistency(eng_starts, j), _consistency(mod_starts, j),
            *meta, float(strategy == "aligned-columns"), float(role == "kv")]


def p_engine(model, f):
    """How likely the engine's split is the right one of the two."""
    z = model["intercept"] + sum(w * x for w, x in zip(model["coef"], f))
    return 1 / (1 + math.exp(-max(-30.0, min(30.0, z))))


def prefer_engine(model, f):
    return p_engine(model, f) > model.get("threshold", 0.5)


def load(path=COEFFS):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def fingerprint(model_dir):
    """A model directory's identity: the SHA-256 of its config.json and of
    every weights file it lists, in order (first 16 hex digits). A retrained
    model has the same shapes and a different fingerprint."""
    h = hashlib.sha256()
    with open(os.path.join(model_dir, "config.json"), "rb") as fh:
        cfg = fh.read()
    h.update(cfg)
    for shard in json.loads(cfg).get("shards", []):
        with open(os.path.join(model_dir, shard), "rb") as fh:
            for block in iter(lambda: fh.read(1 << 20), b""):
                h.update(block)
    return h.hexdigest()[:16]


def load_for_lm(model_dir, default=LM_COEFFS):
    """The arbiter for the tiny LM in model_dir, or None: the directory's own
    arbiter.json (shipped with the model), else `default` when it was fitted
    for this very model (its "model" field is this directory's fingerprint)."""
    if not model_dir:
        return None
    try:
        own = os.path.join(model_dir, "arbiter.json")
        if os.path.isfile(own):
            return load(own)
        if os.path.isfile(default):
            m = load(default)
            if m.get("model") and m["model"] == fingerprint(model_dir):
                return m
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None


def choose(model, roles, eng_starts, mod_starts, probs, meta, strategy):
    """Per line, the split to keep: the engine's where the arbiter prefers it
    and the two differ, else the model's. probs: per line {pos: p} or None.
    Returns (starts per line, number of lines switched to the engine's)."""
    pl = [None if p is None else sorted(p.items()) for p in probs]
    es = [s if s else None for s in eng_starts]
    ms = [s if s else None for s in mod_starts]
    out, switched = list(mod_starts), 0
    for j in range(len(mod_starts)):
        if not ms[j] or not es[j] or sorted(es[j]) == sorted(ms[j]) or pl[j] is None:
            continue
        e_ = [x if x is not None else [] for x in es]
        m_ = [x if x is not None else [] for x in ms]
        if prefer_engine(model, features(e_, m_, pl, j, meta, strategy, roles[j])):
            out[j] = sorted(es[j])
            switched += 1
    return out, switched
