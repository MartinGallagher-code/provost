# docs/archive: what moved out

This directory holds the corpus review rounds' worksheets (marks, batches,
needs and confidence lists, each dated and numbered by round) and old plans:
working records of the review process, not documentation pages. `mkdocs.yml` keeps this
directory out of the built site, and `tests/corpus/prescreen.py --validate`
reads the `review-marks-*.tsv` sheets here.

**Moved out of the tree (PV-042, 2.22.1):** the two prescreen worksheets
`tests/corpus/prescreen.py` wrote in August,
[`review-prescreen-round8.tsv`](https://github.com/MartinGallagher-code/provost/blob/d9c32f046ca1d9457a3ecd7439c2dcf410f85c34/docs/archive/review-prescreen-round8.tsv)
(310,308 bytes) and
[`review-prescreen-2026-08-06-round16.tsv`](https://github.com/MartinGallagher-code/provost/blob/d9c32f046ca1d9457a3ecd7439c2dcf410f85c34/docs/archive/review-prescreen-2026-08-06-round16.tsv)
(300,419 bytes). Nothing reads them, and `prescreen.py -o FILE` writes a
fresh one. They are kept at commit `d9c32f04`, the last that holds them;
restore both, from the top of the checkout, with

```bash
git archive d9c32f046ca1d9457a3ecd7439c2dcf410f85c34 docs/archive/review-prescreen-round8.tsv docs/archive/review-prescreen-2026-08-06-round16.tsv | tar -x
```

(a shallow clone first needs `git fetch --depth=1 origin
d9c32f046ca1d9457a3ecd7439c2dcf410f85c34`). The benchmark rounds' LLM run
records left at the same commit: `tests/benchmark/README.md`, "LLM run
records".
