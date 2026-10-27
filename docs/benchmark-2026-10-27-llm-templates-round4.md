# Round 4 with LLM-written templates: 107 unseen inputs, one template each

**2026-10-27.** This is step 1 of `plan-2026-10-27-near-100.md`: the first
whole-capture measurement of `--llm` on a benchmark round. Round 4
(`docs/benchmark-2026-10-20-generalisation-round4.md`, 107 inputs nobody had
parsed) was built and frozen on 2026-10-20; `--llm` was written on
2026-10-26 against one tool (mcstatus) and had never seen it.

## Method

- **Templates.** Eleven Claude helpers each wrote format-1 templates for ten
  inputs, from `extract/llm/GUIDE.md` and the input alone (no engine, no
  strategies, no corpus, no ratings), checking each with
  `extract/llm/template.py apply` until it covered ≥80% of the lines and
  the records read right. Every template is in
  `tests/benchmark/round4/llm-templates/<stem>.json`, with a `<stem>.note`
  saying `ok` or what format 1 could not express. All 107 compile; 104
  cover 100%, the rest 84–97%. This stands in for `template.py learn`
  (the API path, the same guide, two attempts) because the session has no
  key; a helper iterates more than two times, so this is an upper bound
  on what `learn` would file first time.
- **Run.** `bash tests/benchmark/llm_round.sh --round4`: every input through
  the real CLI (`provost --sync --llm`, a fresh store each) with its
  template offered through `PROVOST_LLM_TEMPLATE_DIRS` and no API key, so
  the hook's own rules decide (a template is tried before auto-multi and the
  model on a held capture, and before a generic parse the gate passed is
  trusted; it must pass the gate's per-block checks, the fragments rule,
  and keep the generic parse's share of data lines within 10 points).
- **Rating.** Eleven other helpers rated the filed datasets on round 4's
  `CRITERIA.md`, reading only the input and the output (not `ratings.tsv`,
  not the templates). Per input: `tests/benchmark/round4/ratings-llm-templates.tsv`
  (with round 4's default and `--multi` ratings beside, and the template's
  note). As in every round, **this is a screen by agents, not a verdict.**

## Headline

| | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| round 4, default engine (2026-10-20) | 12 (11%) | 51 (48%) | 44 (41%) | 59% |
| round 4, `--multi` | 12 (11%) | 64 (60%) | 31 (29%) | 71% |
| **round 4, `--llm` with one template per tool** | **35 (33%)** | **66 (62%)** | **6 (6%)** | **94%** |

The template was used for 102 of 107 inputs; the engine's parse stood for 4
(one `yaml` claim, which is exempt from the gate and so from `--llm`; three
templates the hook's rules declined: a fragments rule on eleven one-row
blocks, a coverage 77% against a 100% `text-lines` parse, a 66%
type-consistency on a two-column table) and 1 was held (a two-line input
whose records all sit on one line).

**Transitions from the default rating:** 9 FAIL→PASS, 31 FAIL→PARTIAL,
17 PARTIAL→PASS; 4 FAIL stayed FAIL (three the template did not replace,
one it did); **5 got worse:** 3 PASS→PARTIAL (010 composer-list: the usage
synopsis line dropped; 011 diagtool-tree: nesting flattened; 117 klog: the
multi-line `err=<` body detached from its event) and 2 PARTIAL→FAIL (019
go-doc-all, 030 jlink-list-plugins: continuation lines dropped where
`text-lines` had kept everything).

### By shape family

| family | n | default P/Pa/F | `--llm` P/Pa/F |
|---|---:|---|---|
| aligned / fixed-width table | 26 | 7 / 10 / 9 | **20 / 6 / 0** |
| multi-section report | 24 | 0 / 12 / 12 | 5 / 18 / 1 |
| log and diagnostic lines | 19 | 1 / 10 / 8 | 4 / 14 / 1 |
| list, grid, help, free text | 11 | 2 / 6 / 3 | 2 / 7 / 2 |
| structured data (trees, dumps) | 10 | 0 / 8 / 2 | 0 / 9 / 1 |
| key/value blocks (several records) | 10 | 0 / 3 / 7 | 0 / 9 / 1 |
| single key/value record | 7 | 2 / 2 / 3 | 4 / 3 / 0 |

### The regex ceiling, measured

Each template's `.note` says whether format 1 (one regex per kind of line)
could express the output. Split the ratings on that:

| format 1 could… | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| express it (`ok`) | 42 | **30 (71%)** | 12 | 0 |
| not: records span lines, titles should be a column, continuation lines, nesting | 65 | 5 (8%) | 54 | 6 |

Where a line-by-line template is the right tool, it is right seven times in
ten and never wrong. Where it is not, the output is almost always PARTIAL
of one kind: **every value lands under the right name, but the parent is
lost** (frames without their thread, members without their pool, items
without their key, rows without their section, continuation lines in a
second table joined only by row order). Raters named this same shape in
nine of the eleven batches. That is exactly what format 2 (a parser, built
the same day) is for, and the 65 notes are its work list.

### What the gate rules did

- The "within 10 points" floor let two templates replace a `text-lines`
  parse that kept every line with one that dropped continuation lines (019,
  030: PARTIAL→FAIL). A template should not beat a lossless parse by
  dropping lines. Step 3 of the plan (a judge pass before a template is
  stored) is the answer; a cheaper first guard is to require a template to
  keep at least the generic parse's share when that parse is a catch-all
  (`text-lines`, `line-records`).
- Three declines were right or harmless (045 prtstat: eleven one-row
  blocks, the engine's `tsv` is a FAIL either way; 046 pydoc: 77% is honest,
  `indent-tree` is PARTIAL either way; 142 idcams: the two-column `entries`
  table failed consistency and the engine's header-from-banner FAIL stood).
- The `yaml` exemption cost one: 020 golangci-lint-linters is a `name:
  description` list that `yaml` pivots into one 110-column row (PARTIAL)
  and the template, which the hook never consulted, splits into a linters
  table.

## Reading this honestly

- Templates were written by helpers who could iterate; `learn` gets two
  attempts. Expect `learn` to land somewhat below this on first contact
  and to recover on the second capture of a tool (the feedback loop).
- The raters were strict on rule 3 (a dropped `(1 row affected)` or a
  version banner is PARTIAL): 127, 130 and 010 are PARTIAL on that reading
  alone. The PASS share is a floor under a lenient reader.
- Round 4 is now seen by `--llm` as well. The next number needs round 5.

## Next

1. Redo the 65 limited templates as format 2 (a parser per tool) and
   re-rate: the plan's step 2 measurement.
2. A judge before storing (step 3), which also fixes the two regressions.
3. With a key in the environment: the same run through `learn` (the API,
   two attempts) to measure the first-contact rate, then the library (step
   5) and round 5.
