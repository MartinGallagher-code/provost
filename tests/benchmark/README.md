# tests/benchmark — inputs the engine has never seen

`tests/corpus/` answers *did this change break something that used to work*.
This answers a different and harsher question: **what happens the first time
provost meets an output nobody wrote a parser for?**

Every corpus entry has been looked at, argued over, and in many cases had a hint
row or a strategy written for it. The corpus score therefore measures how much
work has been done, not how well the engine generalises. These fifty inputs have
no hint row, no strategy, no golden and no prior review.

**Round 1** (`inputs/`, 50 inputs), first rated 2026-08-12: 23 PASS / 12 PARTIAL /
15 FAIL. It has since been tuned against, so it is now a regression set. See
[`docs/benchmark-2026-08-12-generalisation.md`](../../docs/benchmark-2026-08-12-generalisation.md).

**Round 2** (`round2/`, 109 inputs, 2026-10-02): **17 PASS / 51 PARTIAL /
41 FAIL**, measured before any tuning. 67 inputs are real captures and 42 are
faithful reproductions of documented formats; `round2/manifest.tsv` records the
provenance of each. Re-rated 2026-10-14 after the fix round that worked its
patterns 1-4: **26 PASS / 54 PARTIAL / 29 FAIL**. It has now been looked at, so
it is a regression set too. The 2026-10-16 regression check, after the fix
round that worked the rest of its patterns, reads **35 PASS / 63 PARTIAL /
11 FAIL** on these seen inputs, with no output worse. See
[`docs/benchmark-2026-10-02-generalisation-round2.md`](../../docs/benchmark-2026-10-02-generalisation-round2.md)
and its postscripts.

**Round 3** (`round3/`, 107 inputs, 2026-10-16): **22 PASS / 45 PARTIAL /
40 FAIL** (21% / 42% / 37%; 63% usable) on provost 2.1.0. This is the first
measurement of the 2026-10-14 parser work on inputs nobody had parsed. 64
inputs are real captures and 43 are reproductions of documented formats. The
set was novelty-checked against the corpus and rounds 1-2, and frozen with
round 2's criteria before the run. See
[`docs/benchmark-2026-10-16-generalisation-round3.md`](../../docs/benchmark-2026-10-16-generalisation-round3.md).
Re-rated the same day after a fix round whose agents never saw it: **22 PASS /
48 PARTIAL / 37 FAIL** (21% / 45% / 35%; 65% usable). Three FAILs became
PARTIALs, and that small delta is the round's honest generalisation number.
The postscript lists the remaining defects input by input, so round 3 is now
a regression set too. The next generalisation number needs a round 4.

**Round 4** (`round4/`, 107 inputs, 2026-10-20): **12 PASS / 51 PARTIAL /
44 FAIL** (11% / 48% / 41%; 59% usable) on the 2026-10-20 engine (2.1.0 plus
the 2026-10-16 fix round, the 2026-10-20 engine-defect fixes and the quality
gate). 65 inputs are real captures and 42 are reproductions of documented
formats. The set was novelty-checked against the corpus and rounds 1-3, and
frozen (sha256 of every input in `round4/SHA256SUMS`) with round 3's criteria
before the run. Every input also carries a `--multi` rating on the same
scale: **12 / 64 / 31** (71% usable). The quality gate would hold 18
captures: 17 FAIL, 1 PARTIAL, no PASS. See
[`docs/benchmark-2026-10-20-generalisation-round4.md`](../../docs/benchmark-2026-10-20-generalisation-round4.md).
It is a self-assessment screen and is still unseen by any parser fix.

## There is no gate here, on purpose

A pass/fail gate would invite fitting the engine to these fifty files, and the
moment that happens they stop measuring generalisation and start measuring
memorisation — exactly the property that makes the corpus number unable to answer
this question.

So: re-run and read the diff.

```bash
bash tests/benchmark/run.sh /tmp/bench-out                 # round 1
bash tests/benchmark/run.sh --round2 /tmp/bench-r2         # round 2 (~4-5 min, 4 cores)
bash tests/benchmark/run.sh --round2 --tidy /tmp/bench-r2  # + melted .tidy / .multi.tidy
bash tests/benchmark/run.sh --round3 --tidy -j 2 /tmp/bench-r3  # round 3 (107 inputs)
bash tests/benchmark/run.sh --round4 --tidy -j 2 /tmp/bench-r4  # round 4 (107 inputs, ~7 min)
```

Prints a summary line per input: strategy, confidence, input lines, output
lines, the `--multi` dataset count, and the `--rank priority` winner when it
differs. For each input it leaves `.def`/`.meta` (default mode), `.prio`/`.prio.meta`
(`--rank priority`) and `.multi`, which uses the exact flags `provost --multi`
passes (`-f tsv --max-strategies 1`). Since 2026-10-02, `.multi` matches what
provost files. Before that it was plain output from every strategy, so the
`multi` column in round 1's `ratings.tsv` predates the change.

If you fix a defect the ratings call out, update `ratings.tsv` in the same
commit — the file is the record of what was true when, and a stale rating is
worse than no rating.

## Files

| | |
|---|---|
| `inputs/*.txt` | round 1: the fifty inputs |
| `ratings.tsv` | round 1: per-input verdict, cluster and reason; criteria at the top |
| `round2/inputs/*.txt` | round 2: 109 inputs (001-067 captured, 101-142 reproduced) |
| `round2/manifest.tsv` | round 2: provenance, category, shape and source command per input |
| `round2/CRITERIA.md` | round 2: the rating rules, fixed before the run |
| `round2/ratings.tsv` | round 2: winner, confidence, priority winner, rating, `--multi` effect, cluster, reason (2026-10-02); then winner, confidence, line coverage, rating and what changed (2026-10-14 re-rating); then rating and what changed (2026-10-16 regression check) |
| `round2/novelty.py` | round 2: name and content near-duplicate check against every existing input |
| `round3/inputs/*.txt` | round 3: 107 inputs (001-064 captured, 101-143 reproduced) |
| `round3/manifest.tsv` | round 3: provenance, category, family, shape and source command per input |
| `round3/CRITERIA.md` | round 3: round 2's rating rules, reused unchanged and frozen before the run |
| `round3/ratings.tsv` | round 3: default-mode winner, confidence, line coverage, rating and note per input (2.1.0); then winner, confidence, coverage, consistency, rating and what changed (re-rating after the 2026-10-16 fix round) |
| `round3/novelty.py` | round 3: name and content check against the corpus, holdout, round 1 and round 2 |
| `round4/inputs/*.txt` | round 4: 107 inputs (001-065 captured, 101-142 reproduced) |
| `round4/manifest.tsv` | round 4: provenance, category, family, shape and source command per input |
| `round4/SHA256SUMS` | round 4: sha256 of every input, recorded at the freeze |
| `round4/CRITERIA.md` | round 4: round 3's (round 2's) rating rules, reused unchanged and frozen before the run |
| `round4/ratings.tsv` | round 4: default-mode winner, confidence, coverage, consistency, whether the quality gate would hold it, rating, `--multi` dataset count and `--multi` rating, and a note per input |
| `round4/novelty.py` | round 4: name and content check against the corpus, holdout and rounds 1-3 |
| `run.sh` | re-run every input through default, `--rank priority` and `--multi` mode |
| `make_doc_json.sh` | build the workbook JSON (input + melted parse + rating) |
| `make_doc.js` | render that JSON as a markable `.docx` |
| `make_page.py` | render that JSON as a self-contained HTML page |

```bash
bash tests/benchmark/make_doc_json.sh -o /tmp/bench.json
node tests/benchmark/make_doc.js /tmp/bench.json /tmp/benchmark.docx
python3 tests/benchmark/make_page.py /tmp/bench.json /tmp/benchmark.html
```

## Adding inputs

Only add an output the engine has genuinely not been tuned against, and add it
*before* looking at how it parses. An input added after its parse was inspected
is a corpus entry wearing a benchmark's clothes.

## One gotcha, since it cost an hour

`--emit-meta` writes its banner to **stderr**, not into the field stream. Read it
off stdout and every input reports its strategy as "none".
