# ml/ — a small layout model for provost (training tools)

Development-only tooling: **nothing here ships in the wheel or runs when you
use provost.** It builds a training set and trains small models that answer
the two questions provost's heuristics get wrong on unseen formats:

1. **What is each line?** `header`, `row`, `cont` (a wrapped row continued),
   `kv` (one key and its value), `section` (a heading kept as a value), or
   `skip` (rules, banners, prose). `blank` is decided by rule.
2. **Where do fields start?** For each *candidate* offset (a non-space
   character at the start of a line or right after a space or delimiter), is
   this the start of a field? That's what keeps `Mounted on` and
   `Jan 25 00:52` whole while still splitting `100G  40G`.

The models only *label* the input. They never write values, so whatever later
uses the labels cuts every cell from the input itself. The results and what
they mean are in
[`docs/model-2026-10-22-layout-steps1-2.md`](../docs/model-2026-10-22-layout-steps1-2.md).

## Files

| File | What it does | Needs |
|---|---|---|
| `layout.py` | the label vocabulary (roles, candidates) shared by everything | stdlib |
| `corpus_labels.py` | derives labels from `tests/corpus`: lines each golden's cells back up with the raw lines | stdlib |
| `synth.py` | generates labelled synthetic tables/records in 13 layout families | stdlib |
| `dataset.py` | loading, the held-out-family split, scoring, rule baselines | stdlib |
| `features.py` | hand-made features for the tree baseline | stdlib |
| `train_baseline.py` | gradient-boosted trees (LightGBM) | numpy, lightgbm |
| `train_neural.py` | `LayoutNet`, a ~53k-parameter CNN + GRU over the character grid | numpy, torch |
| `show.py` | prints labelled examples for eyeballing | stdlib |
| `tests/test_ml.py` | tests for the label builders (run in CI) | stdlib |

## Reproduce

```bash
python3 ml/corpus_labels.py                      # -> ml/data/corpus.jsonl  (runs the engine, ~4 min)
python3 ml/synth.py -n 4000 --seed 1             # -> ml/data/synth.jsonl
python3 ml/synth.py -n 800 --seed 2 -o ml/data/synth-test.jsonl
python3 -m venv .venv && .venv/bin/pip install numpy lightgbm \
    && .venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
.venv/bin/python ml/train_baseline.py            # ~1 min on 4 cores
.venv/bin/python ml/train_neural.py --epochs 30  # ~15 min on 4 cores, CPU only
python3 -m unittest discover -s ml/tests         # stdlib tests
```

`ml/data/` and `ml/models/` are gitignored: everything in them is regenerated
by the commands above.

## Honesty rules

- **Test on unseen families, not unseen files.** Corpus tools are grouped by
  name prefix (`docker-ps` and `docker-images` go together), and a fixed fifth
  of the families is held out. A model that memorised tools scores badly there.
- **The benchmark rounds stay out.** `tests/benchmark/round*` is never read
  here. Round 4, or a fresh round 5, is how the end-to-end use of the model
  gets measured, once.
- **The corpus labels are provost's own output, not hand labels.** The
  goldens are what the generic parsers produce today, so they carry its
  mistakes (a merged column, a split value). `corpus_labels.py` drops the
  strategies whose output isn't a layout of the input lines, and the files
  whose records don't line up, but some noise stays. The results doc includes
  a hand audit of the disagreements.
