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

## Part 2, the same day: format 2 on the 65 limited inputs

Step 2 of the plan. Ten helpers rewrote the 65 templates whose note named a
cross-line limit as **format-2 parsers** (`round4/llm-templates-f2/`), from
the guide, the input, and the format-1 template with its note (not the
ratings). All 65 compile and apply in the sandbox at 100% coverage. The
round was run again with the format-2 set over the format-1 set
(`llm_round.sh --round4 --templates llm-templates-f2:llm-templates`), and
every input whose filed output changed (63) was rated again by other
helpers, blind as before; the rest carry their format-1 rating
(`round4/ratings-llm-templates-f2.tsv`).

Two gate rules had to change first, because the first format-2 run
declined 23 templates:

- **Type consistency is recorded, not gated, for a template's blocks**
  (`_quality_exempt`). A parser deliberately makes key/value-shaped tables
  (section, key, value) whose value column mixes types; the measure, built
  for homogeneous tables, read 33-66% on 14 good parsers and 0% on a log
  table.
- **The catch-all guard has 20 points of slack** (`_LLM_CATCHALL_SLACK`):
  against `text-lines` a template may skip a fifth of the lines as
  decoration. At 10 it declined seven templates for skipping titles,
  rules and legends.

### Headline

| | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| round 4, default engine | 12 (11%) | 51 (48%) | 44 (41%) | 59% |
| `--llm`, format 1 only | 35 (33%) | 66 (62%) | 6 (6%) | 94% |
| **`--llm`, format 2 where format 1 could not express it** | **86 (80%)** | **18 (17%)** | **3 (3%)** | **97%** |

Of the 65 rewritten inputs: format 1 scored 5 / 54 / 6, format 2 scores
**56 / 8 / 1**. 47 went PARTIAL→PASS and 4 FAIL→PASS; 2 went PARTIAL→FAIL,
both by the catch-all guard, not by a parser (below).

### By shape family

| family | n | default | format 1 | format 2 |
|---|---:|---|---|---|
| aligned / fixed-width table | 26 | 7 / 10 / 9 | 20 / 6 / 0 | **24 / 1 / 1** |
| multi-section report | 24 | 0 / 12 / 12 | 5 / 18 / 1 | **18 / 5 / 1** |
| log and diagnostic lines | 19 | 1 / 10 / 8 | 4 / 14 / 1 | **14 / 5 / 0** |
| list, grid, help, free text | 11 | 2 / 6 / 3 | 2 / 7 / 2 | **8 / 3 / 0** |
| structured data (trees, dumps) | 10 | 0 / 8 / 2 | 0 / 9 / 1 | **7 / 2 / 1** |
| key/value blocks (several records) | 10 | 0 / 3 / 7 | 0 / 9 / 1 | **8 / 2 / 0** |
| single key/value record | 7 | 2 / 2 / 3 | 4 / 3 / 0 | **7 / 0 / 0** |

No family is below 70% PASS. Multi-section reports, which no engine round
ever passed, are at 75%.

### What is left (21 inputs)

- **The catch-all guard, 4** (004 bun-test, 005 bundle-env: declined at
  56% and 75%, filed as `text-lines`, PARTIAL; 112 huawei, 130 sybase:
  declined at 50% and 63%, `text-lines`, rated FAIL because a raw-lines
  dump of a table is "no structure"). In every one of the four the
  skipped lines were decoration or echoes (a legend, dash rules, markdown
  fences, echoed source), and the parser the guard declined would have
  been rated higher. The guard was written for two format-1 regressions
  that format 2 has since fixed (019, 030 are PASS). On this evidence it
  costs more than it saves; it stays only until the judge (step 3) can
  tell dropped data from decoration, which a count cannot.
- **The fragments rule, 1** (132 teamspeak): the whole client list is one
  line; a block of one line with six records is read as a fragment
  (`_AM_FRAG_LINES` counts lines, not records). Held.
- **The `yaml` exemption, 1** (020): the hook never consults a template
  when an exact-format parser claims the input.
- **Format-1 templates that were not rewritten, 10** (their note said
  `ok`), PARTIAL on strict rule-3 readings: a dropped usage line, a
  version banner, a comment cut at a wrap (009, 010, 012, 038, 127, 141),
  or a flat tree (031, 039, 114, 121). A second pass would redo these as
  format 2.
- **Format-2 near-misses, 5**: two `<<<NULL>>>` placeholders dropped
  (006); bit-field sub-nodes collapsed (008); a `#` column colliding with
  the generated row id (124: a provost melt issue, not the template);
  per-line timestamps folded into the request (128); a page header's time
  dropped (142).
- One rater called 046 and 048 borderline PASS; two called 128 and 142
  borderline PARTIAL. The rating noise is about ±2 either way.

### Reading this honestly

- These parsers were written by helpers who could iterate against the
  applier and a hand-made variant; `learn` gets two attempts and no
  variant. The first-contact rate through the API will be lower, and the
  second capture of a tool is where the feedback loop earns it back.
- The helpers wrote for the layout (several checked their parser on a
  variant with other values), but **nothing here measures a template on a
  second capture of the same tool.** That is the generalisation claim the
  whole approach rests on, and it needs its own test (`ml/gen/` can make
  variants; the corpus has a handful of repeats).
- Round 4 is now seen by both formats. The next number needs round 5.

## Part 3: the second capture — does a stored template fit the next run?

The claim the approach rests on: a template written from one capture of a
tool reads the next capture of the same tool. Measured here for the first
time.

- **Inputs.** `round4/variants/`: one more capture of every round-4 tool,
  written by Claude helpers who saw only the original capture and the
  manifest (no template, no parser, no rating), to the tool's format, with
  every value changed, at least one count changed, widths shifted and
  optional parts added or dropped. Some ran the real tool on new scratch
  input (python, redis, ruby, stty, php, pytest, podchecker, prtstat);
  some changed the subject (`go doc container/list`, `php --rc DatePeriod`)
  or the tool version where the output is fixed for an argument or a
  release. Frozen in `variants-SHA256SUMS` before any template ran.
  `variants/README.md` lists how each was made.
- **Run.** The templates stored from the first capture, unchanged
  (`llm-templates-f2` over `llm-templates`), through
  `llm_round.sh --round4 --inputs round4/variants`. No API.
- **Rating.** Blind, as before; raters saw the variant and the output only.
  `round4/ratings-variants.tsv`.

### Headline

| | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| engine, first capture | 12 (11%) | 51 (48%) | 44 (41%) | 59% |
| stored templates, **first** capture (written from it) | 86 (80%) | 18 (17%) | 3 (3%) | 97% |
| stored templates, **second** capture (never seen) | **65 (61%)** | **32 (30%)** | **10 (9%)** | **91%** |

The engine was not rated on the variants; its first-capture score, at
four rounds of 11–21% PASS on unseen output, is the comparison.

**A stored template keeps most of its value on the next run, and loses
about a fifth of its PASSes.** 64 inputs PASS both times; 22 PASS→PARTIAL
or FAIL; 2 got better. By family, tables (19/26 PASS) and key/value
output (15/17) hold up; **logs and diagnostics fall hardest** (14 → 4
PASS of 19): they are where optional line kinds live.

### Why the 23 got worse

One cause underlies nearly all of them: **the second capture contains a
kind of line or part the first one never showed**, and the template was
written from the first.

- **The template no longer covers the capture, so it is declined and the
  engine's parse is filed, 5** (001 apt-get, 002 bison, 025 javap, 037
  ninja, 040 pg_test_fsync). New lines (a NOTE banner, a reduce/reduce
  block, a LocalVariableTable, a compiler warning, `n/a*` footnotes) pull
  the template under its floor, and the fallback is the engine at its
  usual: three of the five are FAIL.
- **The template is used but misses or misreads the new part, 17.** A
  warnings-summary section (048), an exception note read as the exception
  (050), a `WARNING ... at line -` (043), `<Opt=0>` locals (057), LXD
  container rows matching the unit pattern (115), device files spread
  over two continuation lines (110), a lock-announcement block (062),
  `@user` options sorted first (061), a two-value timing line (063), a
  unified diff swallowed by a `skip` pattern (060), wrapped service
  messages (131), a `RETRY LIMIT EXCEEDED` line (137), and so on.
- **The `skip` hole, 1 of those, and the most worrying** (060
  systemd-delta): the template's skip rule took the whole diff block, and
  skipped lines count as covered, so provost reports 100% while the actual
  configuration change is gone. No count can catch this; a reading of the
  output can.
- **Rater variance, about 2** (020, 119: the same parse rated differently
  by two raters).

Nothing here says the template approach is wrong. It says what a template
is: a description of the layout **the tool has shown so far**. The
feedback loop is the missing half.

### What this changes in the plan

1. **Template repair on a miss, before the judge.** A stored template
   knows exactly which lines of a new capture it did not read (unlike the
   engine's coverage, this is exact). When those exist, provost should not
   fall back to the engine: it should send the template, the new capture
   and the unread lines back to Claude to *extend* the template (one call,
   on the first capture of a tool that shows something new), keep the
   extended template only if it still reads the earlier captures stored
   with it, and file with it. Five of the 23 are this case outright, and
   most of the 17 left unread lines.
2. **Skip must be audited.** A template's `skip` lines on a capture should
   be reported (count and a sample) and judged, not counted as covered for
   free: the judge (step 3) reads them; until then, a capture whose skip
   share rises well above the share on the capture the template was
   written from should go to repair.
3. **Keep the captures a template was written from.** Repair and judging
   both need them; the store already commits each capture, so it is a
   matter of recording which captures a template has seen.

With repair, every tool's template converges on its tool's real output
after a few captures; without it, a template is only as good as the first
capture. That is the step that turns 61% on the next run back toward the
80% on the first, and the second-capture test above is the measurement to
rerun after it.

## Part 4: first contact through `learn` (the real API)

Parts 1–3 used templates Claude helpers wrote by iterating against the
applier. Here the product writes them: every round-4 input through
`provost --sync --llm` with a key and **no stored template**
(`llm_round.sh --round4 --learn`), so `template.py learn` (the guide, the
capture, claude-opus-5-5 at effort medium, at most two attempts) wrote each
one and provost's own rules decided whether to file it.

- **Cost:** 108 API calls, **$5.20**, 4.5 minutes at 8 in parallel
  (`round4/llm-templates-learn/llm-log.jsonl`). 104 templates fit their
  capture first time, 2 on the second attempt; one reply came from the
  refusal fallback model (`windows-whoami-priv`). None was over the
  400-line / 64 KB limit.
- **Routing:** 98 filed by the new template (56 format 2, 42 format 1); 8
  by the engine (7 templates declined by the catch-all guard, 1 the `yaml`
  exemption); 1 held (the fragments rule, 132).
- **Rating:** blind, on `CRITERIA.md` (`round4/ratings-learn.tsv`).

| | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| default engine | 12 (11%) | 51 (48%) | 44 (41%) | 59% |
| helper templates, iterated (part 2) | 86 (80%) | 18 (17%) | 3 (3%) | 97% |
| **`learn`, first contact** | **66 (62%)** | **30 (28%)** | **11 (10%)** | **90%** |

| family | n | default | helpers | `learn` |
|---|---:|---|---|---|
| aligned / fixed-width table | 26 | 7 / 10 / 9 | 24 / 1 / 1 | **19 / 6 / 1** |
| multi-section report | 24 | 0 / 12 / 12 | 18 / 5 / 1 | **12 / 8 / 4** |
| log and diagnostic lines | 19 | 1 / 10 / 8 | 14 / 5 / 0 | **10 / 7 / 2** |
| list, grid, help, free text | 11 | 2 / 6 / 3 | 8 / 3 / 0 | **5 / 4 / 2** |
| structured data (trees, dumps) | 10 | 0 / 8 / 2 | 7 / 2 / 1 | **8 / 1 / 1** |
| key/value blocks (several records) | 10 | 0 / 3 / 7 | 8 / 2 / 0 | **6 / 3 / 1** |
| single key/value record | 7 | 2 / 2 / 3 | 7 / 0 / 0 | **6 / 1 / 0** |

**First contact is 62% PASS against the engine's 11%,** on output neither had
seen, for about five cents a tool. 57 inputs went from FAIL or PARTIAL to
PASS; 9 went the other way (1 PASS→FAIL, 2 PASS→PARTIAL, 6 PARTIAL→FAIL).
It is 18 points under the iterated helpers, which is the price of two
attempts and no second look.

Where the 41 that are not PASS come from:

- **The gate, 9** (6 FAIL, 3 PARTIAL): the catch-all guard declined 7
  templates (bun-test, bundle-env, golangci-lint-run, pg_test_fsync, huawei,
  simctl, sybase: each kept 50–72% of the lines `text-lines` kept), and
  the `text-lines` dump stood; the `yaml` exemption (020) and the
  fragments rule (132) as in parts 1–2. The guard is now the largest
  single cause of FAIL on first contact.
- **Information put in `skip`, about 15 PARTIAL:** a version banner
  (047), a usage synopsis (010), a preamble with the test's duration
  (041), a summary line with counts (014, 142), a header section (127,
  114), `ninja: Entering directory` (037), a program output line between
  log lines (038, 062). The guide says "lines that carry no data go in
  skip"; first-contact templates read that generously. This is the skip
  audit the second-capture test asked for, and it would lift more first
  contacts than anything else here.
- **Structure lost, about 9:** a parent or nesting dropped (039, 057, 121,
  065), caller/callee lines with no link (022, FAIL), two layouts under
  one header (063), a multi-line event split (128).
- **A parser's continuation lines turned into columns, 4 FAIL:** body
  lines or later doc paragraphs became spurious keys copied onto every
  record (019 go doc, 046 pydoc, 048 pytest, 117 klog). A judge reading
  the output would catch each one.
- **A row missed, 2:** a regex too narrow for the longest name (140), a
  wrapped comment (012).

## Part 5: template repair on the second capture

The repair part 3 asked for (`template.py misses` / `repair`, wired into
`_llm_template`): a stored template that meets **a kind of line it has not
met** on this capture (left unread, or dropped by a skip pattern; a line's
kind is its first word as printed and the shape of the rest, so another
host in a banner is not new) goes back to Claude **once**, with the
captures it was written from. The extension is kept only if it covers the
new capture at least as well and still reads every line of the earlier
captures that the template read; an unchanged reply is accepted and the
capture remembered, so it is not sent again.

- **Run:** part 3 again, the same stored templates (`llm-templates-f2`
  over `llm-templates`), each given its first capture as its example (what
  `learn` stores now), with a key: `llm_round.sh --round4 --inputs
  round4/variants --examples round4/inputs --learn`.
- **Cost:** 26 repair calls and 1 `learn` (a declined template with
  nothing new to repair), **$1.51**. The other 80 captures were read
  offline, as before.
- **Outcome:** 13 templates extended and kept; 9 sent back unchanged (the
  new kinds were prompts and banners, rightly decoration); 4 extensions
  failed the gate (3 the catch-all guard again, 1 the ±10 floor) and the
  engine stood, as in part 3.
- **Rating:** the 13 inputs whose output changed were rated again, blind;
  the other 94 are byte-identical to part 3's output and keep its rating
  (`round4/ratings-variants-repair.tsv`).

| second capture | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| stored templates, no repair (part 3) | 65 (61%) | 32 (30%) | 10 (9%) | 91% |
| **stored templates, with repair** | **73 (68%)** | **28 (26%)** | **6 (6%)** | **94%** |
| (the same templates on the first capture) | 86 (80%) | 18 (17%) | 3 (3%) | 97% |

5 FAIL→PASS (bison, javap and ninja, which part 3 had declined to the
engine; the chained traceback; **systemd-delta**, whose skip rule had
swallowed a diff at "100%" coverage: the new kinds of skipped line sent it
to repair and the diff is now read), 3 PARTIAL→PASS (podchecker, pytest,
tmux), 4 PARTIAL stayed PARTIAL, 1 PARTIAL→FAIL (031 jstack: extended for
its new SMR lines, then rated FAIL for the frames' missing thread key, the
same flaw part 3's rater called PARTIAL). Logs and diagnostics, the family
part 3 hit hardest, go from 4 to 9 PASS of 19.

**Repair wins back 8 of the 21 PASSes lost between the captures.** What it
cannot reach is the other kind of miss. 11 of the 14 first-PASS inputs
still short left nothing new unread or skipped, so repair never ran:
- **a new kind of line that a pattern matches and misreads:** LXD container
  rows taken for units (115), ioscan's continuation device files under the
  wrong column (110), a value merged into its neighbour (102), wrapped
  service messages (131);
- **structure the template does not keep on this capture:** a field's doc
  comment on its own row (019), one-line init records collapsed (024),
  locals not tied to their method (057), two layouts under one header
  (063), a tree's depth (119), steps in a separate table (108, 137).

No count sees those; a reading of the output (the judge) does.

## Part 6: the whole pipeline, learned then repaired

What a user with a key sees: the templates `learn` wrote on first contact
(part 4, each holding its first capture), meeting the second capture of
their tool, with repair on, and `learn` for the tools first contact kept
no template for (`llm_round.sh --round4 --inputs round4/variants
--templates round4/llm-templates-learn --learn`). All 107 rated blind
(`round4/ratings-variants-learn.tsv`).

- **Cost:** 34 calls (26 repairs, 8 `learn`), **$1.87**, about five cents
  a call. 73 captures were read offline by their stored template: on a
  tool's second capture, about one in three called the API.
- **Routing:** 100 by a template (73 stored as they were, 17 extended, 7
  checked and left as they were, 3 learned now), 6 by the engine (5 the
  catch-all guard, 1 the `yaml` exemption), 1 held (132).

| | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| default engine, first capture | 12 (11%) | 51 (48%) | 44 (41%) | 59% |
| `learn`, first capture (part 4) | 66 (62%) | 30 (28%) | 11 (10%) | 90% |
| **learned templates, second capture, with repair** | **66 (62%)** | **35 (33%)** | **6 (6%)** | **94%** |

The learned templates keep their PASS count on output they were not written
from: 59 PASS both times, 7 PASS→PARTIAL, 7 up to PASS (6 from PARTIAL, 1
from FAIL), and 4 FAIL→PARTIAL. By route: stored as they were 47 / 25 / 1;
extended 11 / 5 / 1; left as they were 6 / 1 / 0; learned now 2 / 1 / 0;
the engine 0 / 3 / 3; held 1 FAIL. Of the 6 FAILs, 4 are the gate (the
catch-all guard twice, the `yaml` exemption, the fragments rule) and 2 a
parser turning continuation lines into columns (048 pytest, 117 klog),
both already FAIL on first contact.

**So the pipeline holds at first-contact quality from one capture to the
next.** For the helpers' templates, repair won back 8 of the 21 PASSes they
lost between captures (part 5). For the learned templates it kept the
level: 7 PASSes lost, 7 gained. What moves the level itself is the judge
(the skip audit, and reading for misread lines) and the gate rules that
decline good templates, not more capture.

## Part 7: a clean-up after extraction

The question asked after part 6: should a phase after extraction get rid of
what is always superfluous (columns, decoration, error lines)? The ratings
said the opposite problem is four times as common: of the non-PASS notes,
about a fifth name junk left in and four fifths information dropped (most
of part 4's PARTIALs were information a template put in `skip`). So the
clean-up moves rather than deletes, and only removes what carries nothing.

- **Values keep to their cells** (`template.py` `_cell` in `flat_records`):
  a tab, CR or newline inside a template's value becomes a space, as the
  engine's `_clean_value` does (without its trim: parsers keep a source
  line's indent on purpose). **All four first-contact FAILs that read as
  "junk columns copied onto every row" were this one bug** (019 go doc, 046
  pydoc, 048 pytest, 117 klog): a format-2 parser joined a multi-line body
  into one value, the flat format is one field per line, and each
  continuation line became a scalar field the melt repeats on every row.
  The helpers' iterated templates never hit it; `learn`'s did 5 times.
- **`NAME.notes`:** the lines a template drops as decoration or does not
  read that still carry a word or a number (a title, a version banner, a
  summary count, a warning, a prompt, an unread line) are filed beside its
  datasets as `NAME.notes` (`line`, `kind` skipped|unread, `text`). Lines of
  rules, box glyphs or carets alone are still dropped.
- **The catch-all guard** no longer counts skipped lines as lost against
  `text-lines` / `line-records`, since they are in the notes; a template
  still has to read 80% of the lines it does not set aside.
- **Not built, on evidence:** across all 602 template tables on round 4
  there is no rule-only row and no repeated header row to drop; and the
  65 all-empty columns are the tool's schema (a column empty this time is
  filled the next, and dropping it would change the dataset's shape from
  capture to capture; raters credited keeping them).

**Measured** (everything rated blind; only outputs that changed were
rated again, the rest keep their rating):

- **First contact** (`round4/ratings-learn-cleanup.tsv`): the same 98
  templates `learn` wrote, offline, plus a new first contact for the 7 the
  old guard declined (`round4/llm-templates-learn-cleanup/`; 8 calls,
  $0.34). 66 outputs changed (55 gained only a notes dataset), all rated
  again.
- **The whole pipeline, second capture**
  (`round4/ratings-variants-learn-cleanup.tsv`): part 6's stored and
  repaired templates plus those 7, with a key (6 calls, $0.26; the 7 new
  templates repaired where they met new kinds of line). 64 outputs
  changed, all rated again.

| | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| default engine | 12 (11%) | 51 (48%) | 44 (41%) | 59% |
| first contact (part 4) | 66 (62%) | 30 (28%) | 11 (10%) | 90% |
| **first contact, with the clean-up** | **87 (81%)** | **18 (17%)** | **2 (2%)** | **98%** |
| the whole pipeline, second capture (part 6) | 66 (62%) | 35 (33%) | 6 (6%) | 94% |
| **the whole pipeline, second capture, with the clean-up** | **83 (78%)** | **22 (21%)** | **2 (2%)** | **98%** |

First contact: 21 up to PASS (7 FAIL, 14 PARTIAL), 2 FAIL→PARTIAL, **none
down**. Second capture: 17 up to PASS (4 FAIL, 13 PARTIAL), **none down**.
The notes did what the "information put in skip" PARTIALs asked for
(pygmentize's version banner, pg_test_timing's duration, ninja's directory,
node's interleaved output, picard's header, bteq's logon lines are all now
kept and rated PASS), the newline fix cleared the four junk-column FAILs,
and all 7 inputs the guard used to leave as a raw-line dump are now filed
by their template (005, 021, 040, 123, 130 PASS; 004, 112 PARTIAL). First contact through the API is now at the iterated helpers'
level (86 / 18 / 3).

**What is left is structure, not loss.** The 2 FAILs are gate rules (the
`yaml` exemption, 020; the fragments rule on a one-line record list, 132).
The ~20 PARTIALs are almost all a parent the template does not keep: an op
tree's nesting (039), iseq headers not applied (057), trunk members (112),
taxonomy depth (119), ioreg's tree (121), caller/callee links (022), which
struct a member belongs to (033), a record split across tables (004, 009,
128), a two-layout header half applied (063), suffixes stripped (014). A
count cannot see any of them; a reading of the output can.

## Next

1. **The judge** (plan step 3), now aimed at structure: one call after
   `learn` and after `repair` that reads the capture and the records and
   answers PASS or a list of fixes (a parent not kept, a record split
   across tables, a header half applied, a new kind of line misread), fed
   back once. Information loss is no longer the main failure: the notes
   keep it.
2. **The gate rules that still cost a FAIL:** the `yaml` exemption keeps
   020 from ever reaching a template; `_AM_FRAG_LINES` counts lines, not
   records, so 132's one-line record list is held every time.
3. Then the library (plan step 5) and **round 5**, built and frozen before
   anything runs: round 4 is now seen by `learn`, repair, the guide and the
   clean-up.
4. Small: the melt should rename a template column that collides with the
   generated row id.
