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
- **Prediction:** about 0.6 s per capture, including its echo; 150 held-out
  captures took 90 s, model load included.

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
| **tiny LM, full run** | *running* | |

**Pilot** (only to check the pipeline): 263 captures, one pass, 6 minutes.
On the first 150 held-out captures it scored **0.450**, against trees 0.833
and engine 0.862 on the same 825 lines. That is barely trained:
- its roles were right on 194 of 233 training lines;
- its start probabilities were high on the true starts but also high on
  candidates after `(` (`CPU(cores)`).

It showed the pipeline works end to end, not what the model can do.

## Reading it

*(to be written when the full run is scored)*
