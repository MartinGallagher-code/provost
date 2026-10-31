# A tiny pretrained LM as the layout labeller, trained on a CPU (2026-10-29)

## Why

provost's learned layout models sit behind `--model`:
- the LightGBM trees, which ship;
- GridNet, about 279k parameters.

They label each line's role and where its fields start. Both learn layout
from scratch on Claude's labels of the corpus (3,674 captures). Both stop at
about 83% of the teacher's splits on tool families they have not seen
(`docs/gridnet-2026-10-23.md`). The bottleneck is data: there is not enough of
it to learn what text looks like.

A pretrained language model already knows what words, numbers, dates, sizes
and units look like. The question here is whether an ultra-small one, small
enough to train and run on a CPU, gets past that plateau when fine-tuned on
the same labels.

## What was built

`ml/train_lm.py` fine-tunes **SmolLM2-135M**. It is a 135M-parameter Llama
model, Apache-2.0, from Hugging Face. It is trained to give the same two
answers as the trees and GridNet, so the whole-table decoder
(`extract/model/decode.py`) and all the scoring are reused unchanged:

- **starts:** for every field-start candidate (`layout.candidates`), whether a
  field starts there;
- **roles:** header / row / cont / kv / section / skip, for every non-blank
  line.

Three design points:

- **Echo.** A causal model only sees what came before a token, but a header
  can only be told from the rows below it. So the input is the capture, a
  separator, then the capture again. Both heads read the *second* copy, where
  every token has seen the whole capture. It is one forward pass and nothing
  is generated, so it is fast, and no value is ever written by the model:
  every value is still cut from the input.
- **Candidate-aligned tokens.** Each line is cut at its candidates before
  tokenizing. So every candidate begins a token of its own, and character
  offsets map to tokens exactly.
- **LoRA.** Rank 16 on every linear layer, plus two small heads: 5.55M
  trained parameters out of 140M. The saved model is those weights (22 MB at
  fp32) and the name of the base model; `--full` fine-tunes everything.

`ml/fold_eval.py --learner lm [--lm-load DIR]` scores it on the usual
yardstick. `ml/tests/test_train_lm.py` tests the encoding, the targets, a
short fit and the `predict_doc` contract on a tiny random model, with no
download. It skips without torch.

## Cost on this machine

The machine: 4-core Xeon at 2.8 GHz with AVX-512, 15 GB RAM, no GPU. Unsloth
needs a GPU, so this is plain PyTorch 2.15 + transformers 5.22 + peft 0.21.

- **Training throughput:** 216–226 tokens a second, including the echo.
- **Memory:** about 9 GB at 2,048 padded tokens a batch. 6,000 tokens a batch
  ran out of memory and was killed.
- **One pass over fold 0's training set:** 2,493 captures, 748k tokens, about
  an hour.
- **Prediction:** about 0.4 s per capture, including its echo. Scoring all of
  fold 0 (627 captures) took 4 m 37 s, including loading the model and
  training the trees beside it.
- **Full run:** two passes over fold 0's training set, 842 steps, about 2 h 5 m
  of the CPU. Validation loss went 0.60 after pass 1, then 0.54 after pass 2,
  so pass 2 was kept.
- **Run alone.** With four training threads on four cores, any other process
  stalls them all: one low-priority job alongside cut training to under half
  speed.

## Results

All scores are on fold 0 of the family cross-validation: 627 held-out
captures and 3,163 lines. The score is how often a line's split matches the
LLM label, on lines where both the engine and the label see fields. "Gold" is
the hand-labelled lines in the fold.

| learner | split | gold |
|---|---:|---:|
| engine (provost's parsers) | 0.814 | 32/48 |
| trees (LightGBM, retrained here) | 0.829 | 32/48 |
| trees + GridNet averaged (documented 2026-10-23) | 0.835 | — |
| **tiny LM (SmolLM2-135M + LoRA), 2 passes** | **0.863** | **39/48** |
| tiny LM and trees, start probabilities averaged | 0.865 | 38/48 |
| tiny LM, continued on 856 corpus captures + 594 generated layouts | 0.854 | 37/48 |

**Pilot** (only to check the pipeline): 263 captures, one pass, 6 minutes.
On the first 150 held-out captures it scored **0.450**, against trees 0.833
and engine 0.862 on the same 825 lines. That is barely trained:
- its roles were right on 194 of 233 training lines;
- its start probabilities were high on the true starts but also high on
  candidates after `(` (`CPU(cores)`).

It showed the pipeline works end to end, not what the model can do.

## Reading it

**The tiny LM clears the plateau the from-scratch models could not.**

- **Against the trees:** it agrees with the teacher on 106 more held-out lines
  (0.863 against 0.829).
- **Against the documented best:** it beats the averaged trees + GridNet
  (0.835).
- **On the hand-labelled lines:** it gets 39 of 48 right, where the trees and
  the engine get 32. Those lines are the answer key that does not come from a
  model.
- **Cost:** a 135M-parameter model, trained for two hours on a 4-core CPU,
  with 5.55M trained parameters.

The hand-labelled lines give the clearest difference, so that is where "a
pretrained model knows what text looks like" pays most.

Averaging it with the trees adds almost nothing: 0.865 overall, one fewer
gold line. The two are not right on complementary lines; the LM is simply
the better reader.

**What it still gets wrong** (`fold_eval.py --show lm 12`). The misses are
mostly judgment calls rather than misreadings:
- `pid /path not confined` read as two cells where the label has three;
- `product:sdk_gphone` kept as one cell where the label splits key from value;
- `Simple mixer control 'Master',0` left whole.

Several of these are cases the guide settles by convention (`key:value`
pairs split), which the model learns only from examples.

**More data of the wrong kind does not help.** Run 2 continued run 1's
model for one pass over half the corpus and 594 layouts from the
Claude-written generators (`ml/gen`, two per generator, from tool families
the corpus does not have). It scored *lower*: 0.854 and 37/48. The pass was
cut at step 600 of 670 by a worker restart, but by then its learning rate
was near zero. So the corpus labels stay the training set, and folds 1 and 2
use run 1's recipe.

**Caveats:**
- Fold 0 alone is one fold of five; the other four (next section) confirm it.
- It is still scored against the teacher's labels (98% right against the hand
  labels), as every learner here is.
- Per-line agreement is not whole-capture quality; the next section measures
  that.

## Cross-validation: all five folds, on an iMac (2026-10-30)

Folds 1–4 never finished in the cloud container. Worker restarts killed fold
1 four times, at steps ~160, ~150, ~180 and 320, and the worker was down from
about 06:06 to 13:50 UTC. Two options came out of that:
- `train_lm.py --start-step N` resumes a killed run at its checkpoint;
- `--device auto` trains on a GPU when there is one, NVIDIA (cuda) or Apple
  (mps).

The user then trained on an iMac with a training kit: the code at 98e7e20a,
`ml/data/`, and a README. The kit was unchanged.
- **The machine:** Apple M4, 24 GB, the GPU (`mps`), the default
  `--batch-tok 2048`.
- **Speed:** about 1,600 tokens a second, 1.1 s a step, about 4.5 times the
  container's speed.
- **Run times:** each of folds 1–4 took 15.5–19 min, and the model on every
  fold (`lm-all`) 21 min.

| learner | fold 0 | fold 1 | fold 2 | fold 3 | fold 4 | all five | gold |
|---|---:|---:|---:|---:|---:|---:|---:|
| engine | 0.814 | 0.785 | 0.832 | 0.828 | 0.803 | 0.814 | 189/287 |
| trees | 0.829 | 0.783 | 0.853 | 0.823 | 0.795 | 0.819 | 212/287 |
| **tiny LM** | **0.863** | **0.849** | **0.893** | **0.856** | **0.842** | **0.862** | **240/287** |
| tiny LM and trees averaged | 0.865 | 0.843 | 0.890 | 0.854 | 0.843 | 0.860 | 235/287 |

The held-out lines per fold are 3,163, 2,431, 3,209, 2,713 and 2,952. "All
five" is the 14,468 lines together, and the gold column is the hand-labelled
lines in every fold.

- **The plateau result holds on every fold.** The tiny LM gets 0.842–0.893.
  - Against the engine it wins by 2.8–6.4 points on each fold, and by 698
    lines in all.
  - Against the trees it wins by 3.3–6.6 points on each fold, and by 626
    lines in all.
- **On the hand-labelled lines** it gets 240 of 287 (84%), against 212 for
  the trees and 189 for the engine. It has the most on every fold.
- **Averaging with the trees does not pay.** It is within 0.006 of the LM
  alone on every fold and gets fewer gold lines (235). Use the LM on its own.
- **Two epochs is about right.** Fold 3 kept epoch 1: its validation loss
  rose in epoch 2 (0.547 to 0.585). Fold 2 and `lm-all` improved only a
  little in epoch 2.

Two things the iMac runs found:
- **The validation families all fell in fold 1.** These runs used that split.
  It is fixed since: a salted hash spreads 346 validation captures over
  folds 1–4, and `train_lm.py --no-val` trains a final model on everything.
  - Why: `dataset.is_val` was `crc32(family) % 10 == 1`, and
    `crossval.fold` is `crc32(family) % 5`, so every validation family had
    fold 1.
  - Effect on the folds: `--fold 1` has no validation set and trains on all
    2,987 of its captures. Every other fold holds back the same 403 and picks
    its epoch on them.
  - Effect on `lm-all`: it trained on 3,271 of the 3,674 captures, not all of
    them.
  - The fold scores are therefore not quite like for like. Fold 2 trained on
    15% fewer captures than fold 1 and still scored highest, so its families
    are easier.
- **`fold_eval.py` crashes on macOS (exit 139)** when LightGBM and torch share
  a process. Two copies of `libomp` are loaded, LightGBM's Homebrew one and
  the one shipped with the Python packages. `OMP_NUM_THREADS=1 ...
  fold_eval.py ... --threads 1` works around it; a fold then scores in about
  80 s. `train_lm.py` never loads LightGBM, so it is unaffected.

## How many layers does it need? (iMac, 2026-10-30/31)

The base model has 30 transformer layers. `--layers N` keeps the first N, to
see how small the model can get before it loses its lead. The user ran the
kit's loop on the iMac:
- the code at 9ebf60de, so the old validation split, the same for every run;
- 2 epochs each, on the M4's GPU.

**Fold 0, every size:**

| layers | parameters | train time | split | gold |
|---:|---:|---:|---:|---:|
| 3 | 40.1M | 2.1 min | 0.796 | 36/48 |
| 6 | 51.2M | 3.7 min | 0.821 | 38/48 |
| 12 | 73.4M | 6.9 min | 0.854 | 39/48 |
| 18 | 95.6M | 10.3 min | 0.876 | 40/48 |
| 30 (all) | 140.1M | 16.8 min | 0.865 | 41/48 |
| *engine* | | | *0.814* | *32/48* |

**18 against 30 layers, all five folds:**

| fold | 18 layers | 30 layers | 18 gold | 30 gold |
|---:|---:|---:|---:|---:|
| 0 | 0.876 | 0.865 | 40/48 | 41/48 |
| 1 | 0.847 | 0.849 | 44/51 | 42/51 |
| 2 | 0.878 | 0.893 | 59/65 | 57/65 |
| 3 | 0.859 | 0.856 | 64/70 | 61/70 |
| 4 | 0.846 | 0.842 | 39/53 | 41/53 |
| **all 14,468 lines** | **0.862** (12,476) | **0.862** (12,477) | **246/287** | **242/287** |

The 30-layer column is the iMac's own five-fold run, rescored with the same
command. Its fold 0 is 0.865 and 41/48, where the cloud CPU run got 0.863
and 39/48. Rerunning on the iMac reproduced its scores exactly.

- **18 layers matches 30.** One line fewer right out of 14,468, and 4 more
  gold lines. Each fold is within 0.015, in both directions. The worst is
  fold 2 (−0.015), which kept epoch 1 on validation loss.
  - It is 68% of the parameters (95.6M against 140.1M).
  - It took 63% of the training time (53 min against 84 for five folds).
- **12 layers is not safe.** It came close on fold 0 (0.854), but on fold 4
  it scored 0.796, below the engine's 0.803.
- **6 and 3 layers** fall towards the engine and below it.
- **So the floor is about 18 layers**, not the 6–12 hoped for.
  - The 18 layers alone are about 64M weights, plus a 28M vocabulary table.
  - Cutting the vocabulary to the tokens provost's captures use would bring
    it to about 70M weights: about 70 MB at 8 bits, or 140 MB at 16.
  - That is still a size that wants a numpy runtime rather than plain
    Python.

**The final 18-layer model, `lm-all-l18`** (the iMac, 2026-10-31):
- **How it was trained:** every fold, 2 epochs, 14 min.
- **Weights:** a 14.5 MB adapter, against 22.4 MB at 30 layers. They stay
  out of git.
- **Validation loss:** 0.540, against 0.563 for the 30-layer `lm-all`.
- **Data:** it was trained with the earlier kit, without `--no-val`. So it
  saw 3,271 captures and held back the 403 old-split validation ones.
- **It loads as 18 layers** through `lm_runtime.load` (95.6M parameters) and
  labels a `df` table right.
- **But whole captures can differ from the 30-layer models.** On round 3's
  `005-cmake-cache-advanced-help`:
  - the trees and the fold-0 30-layer model each file a table (92% and 82%
    of lines);
  - `lm-all-l18`'s labels make nothing fileable, so `--model` declines.

  Per-line scores cannot show that, and round 4 has not been run with it.

## Whole captures: round 4, blind-rated

Round 4 is the held-out benchmark: 107 captures the engine was never tuned
against, rated PASS / PARTIAL / FAIL on its frozen `CRITERIA.md`.
`tests/benchmark/model_round.sh --round4 OUT [--lm DIR]` runs the layout
model **model-first**: every capture is labelled by the model alone and filed
as provost's `--model` path files it (one table or key/value record, else the
model's own sections). There is no engine parse, no quality gate and no
arbiter. So this is a stress test of the labeller on its own, harsher than
`--model` will ever be: `--model` only acts on a capture the gate would hold.

Both outputs were rated blind by subagents in batches of about 18. They saw
the input, the output and the criteria, never which model made it, and
"nothing extracted" is a FAIL.

| reader | filed | read nothing | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|---:|
| default engine (`ratings.tsv`, 2026-10-20) | — | — | **12** | **51** | **44** |
| tiny LM, model-first (fold-0 run 1) | 87 | 20 | 7 | 30 | 70 |
| trees, model-first (shipped) | 94 | 13 | 2 | 32 | 73 |
| tiny LM `lm-all`, model-first (every fold, 2026-10-30) | 90 | 17 | 5 | 31 | 71 |

- **Neither model replaces the engine.** Model-first, the LM fails 70 of 107
  where the engine fails 44. Round 4 is mostly mixed reports, logs and nested
  output, and the model can only file tables, key/value records and its own
  uniform sections. The engine's bespoke strategies read those shapes better.
- **The LM is the better whole-capture reader of the two models,** as it was
  per line. It passes 7 against the trees' 2. Head to head it rates higher on
  14 captures and lower on 7; the other 86 tie.
- **Where it beats the engine** it is on captures the engine fails: 7 FAIL
  become PARTIAL and `017-gio-info-file` becomes a PASS. The engine is better
  on 38. Taking the better of the two on every capture would give 13 / 58 /
  36: that is the ceiling for any arbiter between them, and a picker that
  cannot see the ratings will get less.
- **On the 18 captures the engine's gate holds** (the only ones `--model`
  touches), the engine's parse rates 0 / 1 / 17. The LM reads 5 of them to a
  PARTIAL and loses the one PARTIAL (0 / 5 / 13); the trees manage 0 / 4 /
  14. That is where it would earn its keep.

**How it fails.** 62 of its 70 FAIL notes name content dropped (the summary
line, a key/value block beside a table, most of the records). 21 read
nothing at all. 30 mention headers: a data line taken as the header, a
heading built from content, a section's title read as a column. Nested
derivations, wrapped continuation lines and logs come next. These are
failures of what the model *files*, not of where it cuts: one uniform table
per section cannot hold a tree.

**Training on every fold does not change the whole-capture picture.** The
user's `lm-all` (trained on the iMac on 3,271 captures) was run the same way.
- **Unchanged output:** 39 captures came out byte-identical to the fold-0
  model's, so their ratings carry over.
- **Changed output:** the other 68 were rated blind, as before.
- **The total:** 5 / 31 / 71 against fold 0's 7 / 30 / 70. Head to head, 93
  rate the same, 6 better and 8 worse. That is about the spread two rating
  rounds give anyway.
- **One concrete regression:** on `sge-qhost` it took the first data row
  (`global`) as the header, a PASS that became a FAIL.
- **Where `--model` acts,** the 18 captures the gate holds, it rates
  0 / 2 / 16 against fold 0's 0 / 5 / 13.

More of the same training data moves the per-line score a little and the
whole-capture result not at all. The limit is what the model can file, not
how well it reads lines.

**So the labeller belongs where it is, behind `--model`** (opt in with
`PROVOST_LAYOUT_LM`), as a better second reader for the captures the engine
holds. The engine stays the first reader.
