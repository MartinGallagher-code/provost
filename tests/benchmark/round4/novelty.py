#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Novelty check for the round-4 benchmark set (adapted from round3/novelty.py).

For every round-4 input, find its nearest neighbour among ALL inputs the engine
has been developed or measured against -- tests/corpus/inputs,
tests/corpus/holdout/inputs, tests/corpus/text-inputs, the round-1 set
(tests/benchmark/inputs), the round-2 set (tests/benchmark/round2/inputs) and
the round-3 set (tests/benchmark/round3/inputs) -- on two measures over
normalised text (lowercased, digit runs -> 0, whitespace collapsed, blank
lines dropped):

  line     Jaccard similarity of the sets of normalised lines
  shingle  Jaccard similarity of the sets of word 3-grams

and flag any input whose NAME (tool-mode stem, '_' == '-', case-insensitive)
matches an existing input. Prints one TSV row per input. Round 4 was assembled
so that no input matched by name and no shingle score was high; re-run this
after adding an input to keep that true.

  python3 tests/benchmark/round4/novelty.py            # from the repo root
  python3 tests/benchmark/round4/novelty.py DIR        # screen candidate files in DIR
"""
import glob, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
EXISTING = ['tests/corpus/inputs', 'tests/corpus/holdout/inputs',
            'tests/corpus/text-inputs', 'tests/benchmark/inputs',
            'tests/benchmark/round2/inputs', 'tests/benchmark/round3/inputs']

def norm_lines(text):
    out = []
    for line in text.splitlines():
        line = re.sub(r'\s+', ' ', re.sub(r'\d+', '0', line.strip().lower()))
        if line:
            out.append(line)
    return out

def feats(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        lines = norm_lines(fh.read())
    words = ' '.join(lines).split()
    return set(lines), set(zip(words, words[1:], words[2:]))

def jac(a, b):
    return len(a & b) / len(a | b) if a and b else 0.0

def stem(name):
    return re.sub(r'^\d+-', '', os.path.basename(name)[:-4]).replace('_', '-').lower()

def main():
    target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'tests/benchmark/round4/inputs')
    pool = []
    for d in EXISTING:
        for p in glob.glob(os.path.join(ROOT, d, '*.txt')):
            pool.append((os.path.relpath(p, ROOT), stem(p)) + feats(p))
    names = {s for _, s, _, _ in pool}
    print('input\tname_clash\tline_jaccard\tline_nearest\tshingle_jaccard\tshingle_nearest')
    for c in sorted(glob.glob(os.path.join(target, '*.txt'))):
        L, S = feats(c)
        bl, bs = (0.0, '-'), (0.0, '-')
        for rel, _, l, s in pool:
            a, b = jac(L, l), jac(S, s)
            if a > bl[0]: bl = (a, rel)
            if b > bs[0]: bs = (b, rel)
        clash = 'CLASH' if stem(c) in names else '-'
        print(f'{os.path.basename(c)[:-4]}\t{clash}\t{bl[0]:.2f}\t{bl[1]}\t{bs[0]:.2f}\t{bs[1]}')

if __name__ == '__main__':
    sys.exit(main())
