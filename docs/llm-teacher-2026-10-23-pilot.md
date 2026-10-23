# LLM teacher: pilot on 50 corpus captures (2026-10-23)

## Why

The layout model (`ml/`, `extract/model/`) learned almost entirely from the
engine's own output: the corpus goldens. It can't get much better than what it
copies, and on unseen lines it scores about level with the engine. The plan
is distillation:

1. **A large LLM labels every capture offline**, from the text alone, without
   seeing the engine's output.
2. **A person reviews only the lines where it and the engine disagree.**
3. **A small model trains on the result**, and ships. Nobody needs an LLM at
   capture time.

This pilot measures step 1 on 50 captures: how good the labels are, how often
they disagree with the engine, and what the whole corpus would cost.

## How

- **Guide:** [`ml/llm/GUIDE.md`](../ml/llm/GUIDE.md) gives the label
  format and the conventions.
  - **Format:** for each line, a role (the layout model's `header`, `row`,
    `cont`, `kv`, `section`, `skip`, `blank`) and the line's cells, copied
    verbatim.
  - **Conventions:** written to match the hand labels in
    `ml/eval/gold-*.jsonl`. For example, pipes are decoration, and
    `key=value` pairs split into key and value.
- **Checker:** [`ml/llm/check.py`](../ml/llm/check.py) verifies a label.
  - **What it checks:** every line present once, every cell found in its
    line in order, and rows as wide as their header.
  - **What it produces:** the layout model's vocabulary (a role and field
    starts per line).
  - **`snap`:** moves each start back to the nearest offset the model can
    use.
- **Captures:** 50, picked with a fixed seed (`ml/llm/pilot-2026-10-23.txt`).
  - 40 have lines in the hand-labelled sets (gold, fresh test), so the labels
    can be scored.
  - 10 are captures provost holds back today (no golden).
  - They are small: 467 lines in all.
- **Labeller:** Claude subagents in the working session, five captures each.
  - **Why subagents:** this container has no `ANTHROPIC_API_KEY`.
  - **Independence:** each saw only the guide and its numbered captures. It
    was told not to read the corpus goldens, `ml/eval/`, the engine or its
    strategies.
  - **Checking:** each ran the checker until it printed `ok`.
  - **For the full run:** [`ml/llm/label.py`](../ml/llm/label.py) does the
    same through the API, with the Batches API for half price.
- **Results:** the labels are in `ml/eval/llm-pilot-2026-10-23.jsonl`. The
  numbers below come from
  `python3 ml/llm/score.py ml/eval/llm-pilot-2026-10-23.jsonl`.

## Results

All 50 labels pass the checker.

### Against the hand labels

| lines in these captures | LLM | engine |
|---|---:|---:|
| gold (hand-labelled, 2026-10-22) | **29 / 32** | 18 / 32 |
| fresh test (hand-labelled, 2026-10-22) | 13 / 13 | 13 / 13 |
| together | **42 / 45 (93%)** | 31 / 45 (69%) |

For scale, two careful human labellers agreed on 97% of lines
(`ml/eval/agreement-*.jsonl`).

**The three misses are all decoration, not wrong values:**

- **multipathd, two lines:** a `XXXX....` progress bar. The guide calls bars
  decoration, so the LLM left the bar out and kept `18/20` as the value. The
  hand label keeps the bar together with the count (`XXXXXXXXX. 18/20`). In
  the model's starts-only view, a left-out bar attaches to the cell before it.
- **etcdctl, one line:** the LLM left out the word `is` (in
  `10.0.0.22:2379 is healthy`). The hand label keeps `is healthy` as one
  value.

The second case led to one guide change ("don't drop words"). A second change
came from the disagreement sheet below: syslog `CRON[1442]` splits into
program and pid, as in the hand labels.

> **Caveat:** these two changes came after looking at gold lines and at the
> engine, so a later run's gold score isn't a clean test. The fresh test set
> (137 lines outside the pilot) still is.

### Against the engine (the 40 captures it files today)

| | |
|---|---:|
| line splits agree | 189 / 291 = 65% |
| line roles agree | 260 / 313 = 83% |
| captures where every line agrees | 15 / 40 |

**The 102 lines that differ** are in
[`ml/eval/llm-pilot-review-2026-10-23.md`](../ml/eval/llm-pilot-review-2026-10-23.md),
side by side, with a verdict slot for review.

> **Caveat on the triage below:** it is mine, and I'm the same kind of model
> as the labeller, so it isn't an independent verdict.

| triage | lines | where |
|---|---:|---|
| **the engine is plainly wrong** | ~72 | `git-ls-tree` mode/type/hash merged; `ls -l` dates cut into three; multipathd `1: \| 0: \| 0:`; `ip neigh` keys glued to values; `/proc/stat` and `/proc/interrupts` counters merged into one cell; a header column split because two words have a double space; etcdctl split word by word; fail2ban keys split; argocd / `host` lines dropped |
| **the engine matches the hand convention** | 4 | journalctl pid (the guide is now fixed) |
| **a judgement call either way** | ~26 | `perf stat` metric and unit; `Name <email>`; route keywords as keys; section titles |

**Held-back captures (10):** the LLM labelled 79 of their 90 non-blank lines
as data. Provost files nothing for these today.

### Cost of the whole corpus

The corpus is 3,705 captures, 1.15 MB. The estimate below is scaled from this
sample by input size and priced at list prices (`ml/llm/score.py`). The
Batches API halves these numbers.

| model | if thinking ≈ label length | if thinking ≈ 3× label |
|---|---:|---:|
| claude-opus-5-5 | ~$34 (batch ~$17) | ~$65 (batch ~$33) |
| claude-sonnet-5-5 | ~$17 (batch ~$9) | ~$33 (batch ~$17) |

The real figure will be logged per request in `ml/data/llm/usage.jsonl`.

## What it means

- **The LLM is a much better teacher than the engine.** On hand-labelled
  lines it scores 93% against the engine's 69%, close to the 97% that two
  humans reach.
- **About a third of the lines the engine files are split differently.**
  Most of those look like engine errors. The current model learned them as
  correct.
- **Starts are not enough.** The LLM labels carry each cell's end as well as
  its start, so they can express "this bar or word is decoration". The
  layout model's starts-only vocabulary can't. A next model should predict
  spans, or the starts view should keep decoration with the next value, as
  the hand labels do.

## Next

1. **Label the whole corpus with Claude through the API.** This needs an
   `ANTHROPIC_API_KEY` in the environment:
   ```bash
   python3 ml/llm/label.py --all --batch
   ```
2. **Review the disagreement sheet**, starting with the pilot's 102 lines.
   This also tells us how often the LLM is wrong where the engine is right.
3. **Retrain the tree model on the LLM labels.** This is a cheap test: score
   it on the fresh test set against the current model.
4. **Train the character-grid model**, the step after that.

---

## Full corpus (2026-10-23, same day)

The full run used the API with the user's key: `python3 ml/llm/label.py --all --batch`. It labelled 3,705 captures with claude-opus-5-5 at medium effort, in one Message Batches request, using the guide as revised after the pilot.

- **Cost:** $24.48 in all, including 119 synchronous retries. Every request's usage is logged in `ml/data/llm/usage.jsonl`.
- **Time:** the batch itself finished in under 20 minutes. Collecting the results and running the retries one at a time took about as long again.
- **Labels kept:** 3,674 pass the checker and are kept, in `ml/eval/llm-labels-2026-10-23.jsonl.gz`.
- **Refused:** 25 were blocked by the API's cyber-safety classifier, all password-cracker and scanner output (john, hashcat, gobuster, masscan and similar). `label.py` now records a refusal and doesn't retry it.
- **Failed the checker:** 6 contain control characters that the LLM didn't copy byte for byte: BEL, backspace overstrike, ANSI SGR codes and NBSP digit grouping.

### The teacher

| hand-labelled lines | LLM labels | engine |
|---|---:|---:|
| **fresh test (150)** | **147 (98.0%)** | 126 (84.0%) |
| gold (297 of 300 in labelled captures) | 286 (96.3%) | 192 (64.6%) |

Two careful humans agree on 97% of lines. The fresh test set was never used to tune the guide, so it is the clean number. The gold number is slightly flattered, because the guide's conventions were written to match the hand labels.

Most of the remaining LLM misses are judgement calls. For example, it reads `pid 8821, uptime 2:14:08` as one value where the hand label splits it into key/value pairs, and it gives `Node 0, zone DMA` as one value. Over the whole corpus the LLM's split matches the engine's on 58% of the lines the engine files: 8,931 lines differ.

### The student: the tree model retrained on the LLM labels

5-fold cross-validation by tool family, with the decoder on. The model is the same LightGBM model with the same features. Only the labels change.

| | trained on engine labels (shipped) | trained on LLM labels |
|---|---:|---:|
| **fresh test** | 130 / 150 | **132 / 150** |
| gold | 194 / 300 | **215 / 300** |
| gold, lines where v1 disagreed with the engine | 77 / 150 | **95 / 150** |
| adjudicated A/B lines | **83 / 144** | 72 / 144 |
| matches maintainer-approved engine output | **0.859** | 0.806 |

The last two rows score agreement with the engine's own output, either through an A/B choice that includes the engine's split, or through approved engine output. A model that moves away from the engine loses points there by design.

**What this says:**

- **The teacher is no longer the limit. The student is.** The labels are 98% right, but the tree model learns only a few points from them (130 → 132 on the fresh test).
- **The model's hand-made features can't express what the LLM does.** For example, it keeps `Jul  6 09:12` whole, splits `ip neigh` keys from their values, and treats a column whose header has a double space as one field.
- **That is the case for the next step:** a model that learns its own features from the whole capture (the character-grid model), trained on these labels.
