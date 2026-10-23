# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Check one LLM label file against its capture, and turn labels into the
layout model's vocabulary (a role and field starts per line).

    python3 ml/llm/check.py LABEL.json INPUT.txt     # prints ok, or the problems

INPUT is either the raw capture or the numbered copy the labeller saw
(`N |text` lines). Stdlib only.
"""
import json
import os
import re
import sys

ROLES = {"blank", "header", "row", "cont", "kv", "section", "skip"}
NUMBERED = re.compile(r"^ *(\d+) \|(.*)$")


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = fh.read().split("\n")
    if raw and all(NUMBERED.match(x) for x in raw if x):
        return [NUMBERED.match(x).group(2) for x in raw if x]
    return raw[:-1] if len(raw) > 1 and raw[-1] == "" else raw


def starts_of(text, cells):
    """Field starts for cells copied in order from text, or (None, problem)."""
    out, pos = [], 0
    for c in cells:
        if c is None:
            continue
        if not isinstance(c, str) or not c.strip():
            return None, f"cell {c!r} is empty or not a string"
        k = text.find(c, pos)
        if k < 0:
            k2 = text.find(c.strip(), pos)
            if k2 < 0:
                where = "earlier in the line (out of order)" if c in text else "not in the line"
                return None, f"cell {c!r} {where}"
            k, c = k2, c.strip()
        k += len(c) - len(c.lstrip())
        out.append(k)
        pos = k + len(c.strip())
    return out, None


def snap(text, starts):
    """The layout model's view of a split: each start moved back to the
    nearest candidate offset (layout.candidates), since the model can only
    start a field there. `├─sda1` starts at the glyph; decoration the LLM
    left out stays attached to the field before it."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))), "extract", "model"))
    from layout import candidates
    cands = candidates(text)
    out = []
    for s0 in starts or []:
        c = max([c for c in cands if c <= s0], default=s0)
        if c not in out:
            out.append(c)
    return out


def convert(label, lines):
    """-> (roles, starts, problems); starts[j] is None for lines with no cells."""
    problems, roles, starts = [], [], []
    got = label.get("lines", [])
    if [e.get("n") for e in got] != list(range(len(lines))):
        problems.append(f"expected lines 0..{len(lines) - 1} once each, in order "
                        f"(got {len(got)} entries)")
        byn = {e.get("n"): e for e in got}
        got = [byn.get(j, {"n": j, "role": "skip", "cells": []}) for j in range(len(lines))]
    width = None
    for j, e in enumerate(got):
        role, cells = e.get("role"), e.get("cells") or []
        if role not in ROLES:
            problems.append(f"line {j}: role {role!r} is not one of {sorted(ROLES)}")
            role = "skip"
        if role == "blank" and lines[j].strip():
            problems.append(f"line {j}: 'blank' but the line has text")
        if role in ("blank", "skip") and cells:
            problems.append(f"line {j}: role {role} takes no cells")
            cells = []
        if role in ("header", "row", "cont", "kv", "section") and not [c for c in cells if c is not None]:
            problems.append(f"line {j}: role {role} needs at least one cell")
        if role == "header":
            width = len(cells)
        elif role == "row" and width is not None and len(cells) != width:
            problems.append(f"line {j}: row has {len(cells)} cells but the header above has "
                            f"{width} (use null for an empty column)")
        elif role not in ("row", "cont", "blank"):
            width = None if role != "skip" else width
        st, why = starts_of(lines[j], cells)
        if why:
            problems.append(f"line {j}: {why}")
            st = []
        roles.append(role)
        starts.append(st if st else None)
    return roles, starts, problems


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        with open(argv[0], encoding="utf-8") as fh:
            label = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"not valid JSON: {exc}")
        return 1
    _, _, problems = convert(label, read_lines(argv[1]))
    if problems:
        print("\n".join(problems))
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
