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
it is a regression set too; the next generalisation number needs a round 3. See
[`docs/benchmark-2026-10-02-generalisation-round2.md`](../../docs/benchmark-2026-10-02-generalisation-round2.md)
and its postscript.

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
| `round2/ratings.tsv` | round 2: winner, confidence, priority winner, rating, `--multi` effect, cluster, reason (2026-10-02); then winner, confidence, line coverage, rating and what changed (2026-10-14 re-rating) |
| `round2/novelty.py` | round 2: name and content near-duplicate check against every existing input |
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
