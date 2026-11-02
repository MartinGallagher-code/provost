# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""How the tiny-LM labeller sees a capture, shared by training (ml/train_lm.py),
the torch runtime (lm_runtime.py) and the numpy one (lm_numpy.py). Stdlib
only, so the numpy runtime never imports torch.

The capture is echoed (capture, separator, capture again) and the heads read
the second copy, so a causal model sees the rows below a header; each line
is cut at its field-start candidates before tokenizing, so every candidate
begins a token.
"""
import json
import os

from layout import PREDICTED, candidates, is_blank  # noqa: F401  (is_blank, candidates: re-exported)

SEP = "\n=====\n"        # between the two copies
MAX_TOK = 640           # tokens per copy of a window (lines are kept whole)
MAX_LINE = 400          # characters of a line the model sees; later candidates score 0
NUMPY_FORMAT = "provost-lm-numpy/1"   # config.json "format" of an export_lm.py model


def is_numpy_dir(path):
    """True when path holds a model ml/export_lm.py wrote (lm_numpy runs it)."""
    try:
        with open(os.path.join(path, "config.json"), encoding="utf-8") as fh:
            return json.load(fh).get("format") == NUMPY_FORMAT
    except (OSError, ValueError, AttributeError):
        return False


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
