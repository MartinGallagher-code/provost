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
- This is one fold of five: 627 captures from the families it never saw.
- It is still scored against the teacher's labels (98% right against the hand
  labels), as every learner here is.
- It says nothing yet about whole captures. That needs it behind `--model`
  and a blind benchmark round.
