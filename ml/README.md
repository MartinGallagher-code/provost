# ml/ — a small layout model for provost (training tools)

Development-only tooling (the label vocabulary `layout.py`, the features `features.py` and the whole-table decoder `decode.py` live in `extract/model/`, because provost runs them at capture time; everything here imports them from there): **nothing here ships in the wheel or runs when you
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
| `corpus_labels.py` | derives labels from `tests/corpus`: lines each golden's cells back up with the raw lines | stdlib |
| `synth.py` | generates labelled synthetic tables/records in 13 layout families | stdlib |
| `dataset.py` | loading, the held-out-family split, scoring, rule baselines | stdlib |
| `train_baseline.py` | gradient-boosted trees (LightGBM) | numpy, lightgbm |
| `train_neural.py` | `LayoutNet`, a ~53k-parameter CNN + GRU over the character grid | numpy, torch |
| `train_grid.py` | `GridNet`, a ~279k-parameter axial model (row convolutions, column attention) that learns its own features; `crossval.py --learner grid` scores it | numpy, torch |
| `train_lm.py` | a tiny pretrained language model (SmolLM2-135M, LoRA) fine-tuned to the same two answers: the capture is echoed so a causal model sees the rows below a header, and each line is cut at its candidates before tokenizing; `fold_eval.py --learner lm` scores it. Results: `docs/lm-2026-10-29-tiny-labeller.md` | torch, transformers, peft (CPU is enough) |
| `export_grid.py` | writes GridNet's float16 weights for `extract/model/gridnet.py` (numpy-only forward pass) and checks it matches torch | numpy, torch |
| `gen/` | 297 format generators written by Claude (`gen/tools/`, one real tool each, all from tool families the corpus doesn't have), the `Doc` builder they use (`gen/lib.py`), and `gen/run.py`, which checks them and writes `ml/data/gen.jsonl` | stdlib |
| `fold_eval.py` | one cross-validation fold scored against the LLM labels: the quick development yardstick for learners and extra training sets | numpy, lightgbm, scikit-learn (+ torch for GridNet; + transformers, peft for `--learner lm`) |
| `crossval.py` | whole-corpus comparison with the engine: 5-fold cross-validation by family, plus a blind A/B sheet of disagreements for independent judging | numpy, lightgbm |
| `adjudicated.py` | the answer keys that don't come from the engine: builds and scores `eval/adjudicated-*.jsonl` (150 blind A/B verdicts) and `eval/gold-*.jsonl` (300 hand-labelled lines) | stdlib |
| `eval/` | those sets, plus the LLM labels of the whole corpus (`llm-labels-*.jsonl.gz`) and the pilot's labels and review sheet (`llm-pilot-*`) — committed, because they are review work, not regenerable | data |
| `export_model.py` | compiles the trained trees into `extract/model/layout-model.json.gz` (the shipped model) | lightgbm |
| `export_lm.py` | turns a `train_lm.py` model into the numpy runtime's (`extract/model/lm_numpy.py`): the adapter merged, 8-bit weights in `.npz` shards, the tokenizer for `extract/model/bpe.py`; `--check N` compares it with torch. The `provost-model` package is its output | torch, transformers, peft, numpy |
| `arbiter.py` | picks the engine's or the model's split per line (logistic regression) | numpy, scikit-learn to train |
| `show.py` | prints labelled examples for eyeballing | stdlib |
| `llm/GUIDE.md` | the labelling guide the LLM teacher follows (also the API run's system prompt) | text |
| `llm/check.py` | validates one LLM label and turns it into roles + field starts | stdlib |
| `llm/label.py` | labels corpus captures with Claude through the Anthropic API (`--batch` for half price) | anthropic, `ANTHROPIC_API_KEY` |
| `llm/score.py` | scores LLM labels against the hand labels and the engine; cost estimate; review sheet | stdlib |
| `llm/to_corpus.py` | turns LLM labels into a training set (`crossval.py --train-corpus`, `train_baseline.py --corpus`) | stdlib |
| `tests/test_ml.py`, `tests/test_llm.py` | tests for the label builders and the LLM-label checker (run in CI) | stdlib |
| `tests/test_train_lm.py` | tests for the tiny-LM labeller on a tiny random model (no download); skipped without torch/transformers/peft | torch, transformers, peft |
| `tests/test_lm_numpy.py` | the tiny LM without torch: the tokenizer (stdlib), the numpy forward pass (checked against transformers' Llama where torch is installed), the quantizers, the export layout | numpy |

## Reproduce

```bash
python3 ml/corpus_labels.py                      # -> ml/data/corpus.jsonl  (runs the engine, ~4 min)
python3 ml/synth.py -n 4000 --seed 1             # -> ml/data/synth.jsonl
python3 ml/synth.py -n 800 --seed 2 -o ml/data/synth-test.jsonl
python3 -m venv .venv && .venv/bin/pip install numpy lightgbm \
    && .venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
.venv/bin/python ml/train_baseline.py            # ~1 min on 4 cores
.venv/bin/python ml/crossval.py --clean 0.05 --fix-labels   # whole corpus + hand labels, ~3 min
.venv/bin/python ml/train_baseline.py --final --corpus ml/data/corpus-llm.jsonl --extra ml/data/synth.jsonl --save ml/models/llm   # the SHIPPED model (2026-10-26): LLM labels + synth
.venv/bin/python ml/export_model.py --roles ml/models/llm/baseline-final-roles.txt --starts ml/models/llm/baseline-final-starts.txt
.venv/bin/python ml/crossval.py --train-corpus ml/data/corpus-llm.jsonl --extra ml/data/synth.jsonl --decode --out ml/data/crossval.jsonl
.venv/bin/python ml/arbiter.py --crossval ml/data/crossval.jsonl --meta DIR --save extract/model/arbiter.json   # DIR: engine --batch --generic metas
.venv/bin/python ml/train_neural.py --epochs 30  # ~15 min on 4 cores, CPU only
.venv/bin/pip install transformers peft scikit-learn   # the tiny LM (downloads SmolLM2-135M, ~270 MB)
.venv/bin/python ml/train_lm.py --fold 0 --epochs 2 --save ml/models/lm-f0   # ~1 h per epoch on 4 cores, ~9 GB RAM
.venv/bin/python ml/fold_eval.py --fold 0 --learner lm --lm-load ml/models/lm-f0/best
.venv/bin/python ml/train_lm.py --fold 0 --epochs 2 --layers 6 --save ml/models/lm6-f0   # the first 6 of 30 layers: 51M weights
.venv/bin/python ml/export_lm.py --model ml/models/lm-all-l18 --out ../provost_model/src/provost_model/model --check 200   # the provost-model package
# fold_eval keeps LightGBM and torch in separate processes (the torch learner trains in a
# spawned child): on macOS their two libomp copies in one process crashed it (PV-014)
python3 -m unittest discover -s ml/tests         # stdlib tests
# LLM teacher (needs `pip install anthropic` and ANTHROPIC_API_KEY; ~$25 for the corpus):
python3 ml/llm/label.py --all --batch            # -> ml/data/llm/<tool>.json (+ usage.jsonl)
python3 ml/llm/to_corpus.py ml/eval/llm-labels-2026-10-23.jsonl.gz   # the committed labels -> ml/data/corpus-llm.jsonl
.venv/bin/python ml/crossval.py --train-corpus ml/data/corpus-llm.jsonl --decode   # learn from the LLM, score as before
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
