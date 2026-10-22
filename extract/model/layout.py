# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Shared vocabulary for the layout model: line roles and field-start candidates.

Stdlib only. The training set (corpus_labels.py, synth.py) and the models
(train_*.py) both import this, so a label means the same thing everywhere.

A labelled example is one JSON object per input:

    {"name": ..., "source": "corpus"|"synth", "strategy"/"style": ...,
     "lines":  [str, ...],          # the raw lines, tabs kept
     "roles":  [ROLE, ...],         # one per line
     "starts": [[int, ...]|null]}   # per line: field-start offsets, or null
                                    #   when the line's fields are unknown

Roles describe the INPUT line, whatever shape the golden table took:

    blank    whitespace only (decided by rule, never predicted)
    header   names the columns of the rows below it
    row      one whole record on one line
    cont     continues the record started on an earlier line (wrapped row)
    kv       one key and its value
    section  a stand-alone heading/title whose text is kept as a value
    skip     everything else: rules, banners, prose, totals that were dropped
"""

ROLES = ["blank", "header", "row", "cont", "kv", "section", "skip"]
PREDICTED = ROLES[1:]  # blank is decided by rule
ROLE_ID = {r: i for i, r in enumerate(ROLES)}

# Characters that end one field and can precede the next. A field-start
# candidate is a non-space character at the start of the line or right after
# one of these; the boundary model decides which candidates really start a
# field (so "Mounted on" stays one field and "10:00:01" is not split).
DELIMS = set(" \t,;|:=[](){}<>\"'│┃║¦")


def is_blank(line):
    return not line.strip()


def candidates(line):
    """Offsets where a field could start."""
    out = []
    for i, ch in enumerate(line):
        if ch in " \t":
            continue
        if i == 0 or line[i - 1] in DELIMS:
            out.append(i)
    return out


def fields(line, starts):
    """Cut a line at the given field starts (the interpreter's view)."""
    out = []
    for k, s in enumerate(starts):
        e = starts[k + 1] if k + 1 < len(starts) else len(line)
        out.append(line[s:e].strip().rstrip("|│┃║,;").strip())
    return out
