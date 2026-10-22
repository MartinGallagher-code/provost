# A small layout model, steps 1-2: a training set and first models

**2026-10-22.** This is the first measurement of whether a small learned model
can do the part of provost's job that heuristics do badly on unseen formats.
It doesn't change provost: everything is training-time tooling under
[`ml/`](https://github.com/MartinGallagher-code/provost/blob/main/ml/README.md). Wiring a model into provost and measuring end to end
is step 3, not done yet.

## The task

The model answers two questions about the raw text. It never writes values,
so whatever uses its answers still cuts every cell from the input.

1. **Line roles:** `header`, `row`, `cont` (a wrapped row continued), `kv`,
   `section` (a heading kept as a value) or `skip`. `blank` is decided by
   rule.
2. **Field starts:** at each candidate offset (a non-space character at the
   start of the line or after a space or delimiter), does a field start
   here? That's the decision that keeps `Mounted on`, `5 minutes ago` and
   `12:30:01 AM` whole while still splitting `100G  40G`.

## Step 1: the training set

**Corpus labels (`ml/corpus_labels.py`).** Each frozen golden's cells are
lined back up with the raw lines, record by record and in order. Cells can
span whitespace runs, because goldens collapse padding inside a value. Each
line then gets a role from how its record matched:

| How the record matched | Role |
|---|---|
| whole record on one line | `row` |
| a key-shaped golden (key/value, name/value) | `kv` |
| the record continued on further lines | `cont` |
| a column value found on an earlier line | `section` |
| the line that names the columns | `header` |
| a key/value line whose value is empty | `kv` |

Of 3,584 goldens:

- **478 dropped by strategy:** the output isn't a layout of the input lines
  (JSON/XML grammars, trees with derived depth/parent columns, the
  `text-lines` catch-all, `vertical-line`).
- **275 dropped because their records didn't line up** (under 90% matched).
- **2,831 kept:** 18,231 labelled lines, and every field start is checked
  against the candidate rule.

**Synthetic labels (`ml/synth.py`).** 4,000 generated documents (plus an
800-document test set from another seed) in 13 layout families:

- aligned tables: with and without headers, rules, overflowing columns,
  wrapped rows, and a free-text last column
- pipe, box and delimited tables
- `key: value` blocks and block records
- sectioned tables
- a key/value preamble followed by a table
- lists, logs, and inline `k=v` lines

Banners and footers are added around them. Labels are exact.

**Split.** Corpus tools are grouped into families by name prefix
(`docker-ps` and `docker-images` go together), and a fixed fifth of the
families is the test set: **2,204 training documents and 627 test documents**.
For epoch choice the neural model also sets aside 290 training documents
from their own families. `tests/benchmark/` is never read.

## Step 2: models

- **Rule baselines:** split on every whitespace run (awk's default), or on 2+
  spaces, a tab or `, ; |`. For roles, the majority class.
- **Trees (`ml/train_baseline.py`):** LightGBM on hand-made features. Per line:
  shape, delimiters, `key: value` patterns, rule lines, and alignment with
  neighbouring lines. Per candidate: the gap before it, character classes,
  tokens, and how many lines within ±6 have a space or a candidate at the same
  column.
- **LayoutNet (`ml/train_neural.py`):** 52,615 parameters.
  - A 2-D CNN runs over the character grid, so it sees across and down at
    once; a column gutter is a vertical stripe of spaces.
  - It has a per-cell field-start head, and a bidirectional GRU down the lines
    for roles.
  - It trains on CPU in about 35 s per epoch.

## Results (held-out corpus families: 3,744 lines, 3,250 with known fields)

| model | trained on | role acc | role acc, row≈kv | role macro-F1 | **lines split exactly right** | field-start F1 | size |
|---|---|---:|---:|---:|---:|---:|---:|
| majority class / split on whitespace | — | 0.609 | — | 0.126 | 0.540 | 0.833 | — |
| split on 2+ spaces, tab, `,;\|` | — | — | — | — | 0.472 | 0.836 | — |
| trees | synthetic only | 0.801 | 0.915 | 0.543 | 0.663 | 0.898 | |
| **trees** | **corpus** | **0.868** | **0.946** | **0.705** | **0.772** | **0.929** | 3.3 MB gz |
| trees | corpus + synthetic | 0.857 | 0.940 | 0.680 | 0.743 | 0.929 | |
| LayoutNet | corpus | 0.821 | 0.919 | 0.586 | 0.626 | 0.899 | |
| LayoutNet | corpus + synthetic | 0.842 | 0.918 | 0.586 | 0.673 | 0.912 | |
| LayoutNet + dropout, indent augmentation, epoch chosen on validation | corpus + synthetic | 0.852 | 0.934 | 0.600 | 0.687 | 0.915 | **0.10 MB** |

"row≈kv" counts row and kv as one class. A two-field `version  2.4.1` line is
a `row` in one golden and a `kv` in another, depending on the shape the
generic parser picked. Most of the strict role errors are that confusion.

Per-role F1 for the best tree model:

| header | row | kv | skip | cont | section |
|---:|---:|---:|---:|---:|---:|
| 0.89 | 0.91 | 0.76 | 0.80 | 0.50 | 0.35 |

`cont` and `section` are weak. They have few examples (279 and 350) and the
noisiest labels.

## How much of the error is the labels? A hand audit

The corpus labels are provost's own output, so a disagreement isn't
necessarily a model error. Forty of the best tree model's 742 disagreeing
lines were drawn at random and judged by hand:

| verdict | count | typical case |
|---|---:|---|
| model wrong | 21 | splits a timestamp (`Wed 2026-07-01 21:18:07 UTC`, `Jul 11 08:01:00`); splits a multi-word key (`Max cpu time`); misses a last column |
| label wrong, model right | 11 | golden split `5 minutes ago`, `12:30:01 AM`, `Maître & Cie`, `"node server.js"`; golden merged two real columns (`ncurses  ncurses library`, yum's repo column, iperf3's columns behind `[  5]`) |
| either defensible | 8 | `STAT uptime 884512` with or without `STAT`; `4821 / 5102 (94.49%)` as one field or two |

If that sample is typical, about a third of the measured line errors are label
errors. The trees' real rate is then roughly **83-86% of lines split exactly
right**, against 77% measured. The sample is small (±15 points on each share).
Lines where model and label agree on the same wrong answer aren't measured
at all.

## What this says

1. **A learned model beats the heuristics by a wide margin on unseen
   families.** Exact splits go from 54% (split on spaces) to 77% measured,
   about 85% after the audit, and roles reach 87% (95% counting row≈kv).
   These are the two decisions the generic parsers get wrong on new formats.
2. **The trees beat the small neural model at this data size.** They lead on
   every measure. LayoutNet is about 30 times smaller (100 KB against 3.3 MB),
   and three rounds of tuning closed only part of the gap (63% → 69% exact).
   With 2,200 real documents, hand-made alignment features carry more than a
   CNN can learn.
3. **Synthetic data, as built, mostly teaches itself.**
   - Both models score 96-99.9% on synthetic test data.
   - Trained on synthetic data alone, the trees reach 66% on real tools: well
     above the rules, well below corpus training.
   - Adding synthetic data to the corpus slightly *hurts* the trees and helps
     LayoutNet by 4-5 points.
   - The generator's layouts are too regular. The audit's error list (real
     timestamp formats, multi-word keys, ragged last columns) says what to add.
4. **The labels are now the main limit.** At roughly one label error per
   three disagreements, more model capacity would mostly learn provost's
   mistakes. Hand-correcting a few hundred labelled lines, starting with the
   audit's error kinds, is probably worth more than any model change.

## Honesty notes

- About eight configurations were compared on the test families: three
  training mixes for the trees, three for LayoutNet, and two label and
  generator revisions. That's mild selection on the test set. LayoutNet's
  epoch was chosen on a separate validation split; the trees have no tuned
  settings.
- `tests/benchmark/round4` hasn't been read by any of this, so it can still
  measure step 3 once, end to end. After that, a round 5 is needed.

## Step 3 (not done)

- **Use the trees.** Gzipped, the two models are 3.3 MB, well inside a
  normal wheel.
- **No new dependency.** A gradient-boosted tree is a list of if/else nodes,
  so a ~100-line pure-Python evaluator can read LightGBM's text dump without
  installing lightgbm or numpy. A typical capture's lines and candidates need
  a few hundred thousand node steps, a fraction of a second.
- **Wiring:** behind `PROVOST_MODEL`, off by default. Run it only on captures
  the quality gate would hold. Accept its parse only if it passes the same
  coverage and consistency gate. Measure once on round 4.
