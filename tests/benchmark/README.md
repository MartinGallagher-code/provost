# tests/benchmark — 50 inputs the engine has never seen

`tests/corpus/` answers *did this change break something that used to work*.
This answers a different and harsher question: **what happens the first time
provost meets an output nobody wrote a parser for?**

Every corpus entry has been looked at, argued over, and in many cases had a hint
row or a strategy written for it. The corpus score therefore measures how much
work has been done, not how well the engine generalises. These fifty inputs have
no hint row, no strategy, no golden and no prior review.

**Result as of 2026-08-12: 23 PASS / 12 PARTIAL / 15 FAIL.** Analysis in
[`docs/benchmark-2026-08-12-generalisation.md`](../../docs/benchmark-2026-08-12-generalisation.md).

## There is no gate here, on purpose

A pass/fail gate would invite fitting the engine to these fifty files, and the
moment that happens they stop measuring generalisation and start measuring
memorisation — exactly the property that makes the corpus number unable to answer
this question.

So: re-run and read the diff.

```bash
bash tests/benchmark/run.sh /tmp/bench-out
```

Prints a summary line per input (strategy, confidence, input lines, output lines,
`--multi` dataset count) and leaves `.def`, `.meta` and `.multi` files for each.

If you fix a defect the ratings call out, update `ratings.tsv` in the same
commit — the file is the record of what was true when, and a stale rating is
worse than no rating.

## Files

| | |
|---|---|
| `inputs/*.txt` | the fifty inputs |
| `ratings.tsv` | per-input verdict, cluster and reason; criteria at the top |
| `run.sh` | re-run every input through default and `--multi` mode |
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
