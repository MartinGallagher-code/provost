# Handoff — provost

The history that used to live here (2026-07 → 2026-09-16, ~100 KB) is in git:
`git show 9f9d7c0:HANDOFF.md`. `CHANGELOG.md` has the dated detail.

## Present state (2026-10-23; commands and store format updated 2026-10-28; `batch` and four readers 2026-10-29)

**provost 2.2.0 is everything through 2026-10-29** (`VERSION`, man header, the
release entry at the top of CHANGELOG). It is published by running the
"Release to PyPI" workflow on `main` (or a GitHub release tagged `v2.2.0`,
not both); PyPI's provost page says whether that has happened. 2.1.0
(2026-10-16) was the first release with the rename, store format 2, line
coverage and the 2026-10-14 parser work. 2.2.0 adds the quality gate and
auto-multi, the engine fixes, removal of the legacy names, store format 3,
browsing and search, `batch`, the opt-in `--llm` and `--model`, and the
2026-10-29 readers.

provost is one Bash entry point (`provost`) over:
- the extract engine (`extract/provost-extract`, 268 strategies, ~116 generic)
- the tidy melt (`transform/melt.sh`)
- the analyze engine (`analyze/provost-analyze`)

It has a git-backed store and ships as a thin Python launcher
(`src/provost_data/`).

### The honest picture: generalisation

| measure | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| round 2, first rating (unseen, 2026-10-02) | 16% | 47% | 38% | 62% |
| round 3 on 2.1.0 (unseen) | 21% | 42% | 37% | 63% |
| round 3 after the 2026-10-16 round (unseen by its fixers) | 21% | 45% | 35% | 65% |
| round 2 after both rounds (seen: a regression set) | 32% | 58% | 10% | 90% |

**On output provost has never seen, about one input in five is fully right and
about one in three is wrong, and two fix rounds have barely moved that.**
They have moved the seen sets a lot. The gap between round 2 (90% usable)
and round 3 (65%) measures how much the fixes fit what their authors could
see. The corpus figure (3677 / 3705 tidy) is a shape check on tuned inputs,
not a quality measure.

Round 3 is now seen too, so the next honest number needs a **round 4**. Build
it, freeze it and rate it before any fix, as round 3 was
(`tests/benchmark/round3/`, `docs/benchmark-2026-10-16-generalisation-round3.md`).

### This round (2026-10-16, PR #76)

- **Round 3 benchmark:** 107 inputs, rated on 2.1.0 and then once after the
  round.
- **Column-type consistency:** a 5th `--emit-meta` field and a guarded
  consistency hold. It fixed about a dozen corpus misparses but replaced only
  1 of 11 held round-3 claims. Like coverage, it only warns one way: a
  uniformly shifted header scores 100.
- **Whitespace tables:**
  - a UTF-8-aware gutter grid
  - headerless first rows
  - footers handled in every table parser
  - print-report and pprof banners
- **Format parsers decline what they don't understand:** toml, equals, yaml,
  csv, semicolon-values, colon-fields and colons.
- **New `section-tables`** (titled sub-tables in one table with a section
  column), and indentation kept as depth/parent.
- **Pre-rename `ENVOY_*` / `MFE_*` fallbacks removed**; this ships in 2.2.0.
- **Corpus:** 3583 golden passes, 0 failed. COVERAGE.md shows 3677 / 3705.

`tests/corpus/*/envoy-*` are real Envoy-proxy captures, not leftovers.

Behaviour worth knowing:

- `provost run CMD` names the dataset after the command. Piped input is named
  after the winning parser. `--name` overrides both.
- Background capture only at an interactive terminal; scripts run
  synchronously. Failures: `provost log --failed`.
- Captures and `rm` are refused while `provost restore <id>` (or `prev` /
  `next`) has a capture out; `show --at`, `source ID`, `search --at`,
  `files` and `diff` read any capture from git without moving the store.
- Every dataset row is `#` (unique in the store), `capture` (`c0007`), `n`
  (record within that capture), then the data (store format 3).
- In a controlled directory each capture also commits the directory's files
  (`files-<id>` tags, chained); `provost files`, `provost diff`.
- `provost batch FILE...` files many inputs as one commit, a capture each
  (parse halves in parallel, store halves under one lock). With
  `--context-columns` a `#%` prologue's `key=value` words become row columns.
- A store whose `.git/config` others can write is refused if it sets keys that
  make git run programs.
- Engines run with `PROVOST_NO_RC=1`.
- Detection steps, in order:
  1. best confidence wins, with exact ceiling pruning;
  2. the coverage hold (`kv-report` rescue);
  3. the consistency hold.

  `--rank priority` gives the old first-match order. `--emit-meta` prints
  strategy, confidence, coverage and consistency.
- Large inputs: above 32 KB, detectors screen a sample (head, tail and middle
  windows) and the winner is re-confirmed on the full text.

Suites (all CI-enforced):
- `tests/smoke.sh` (478)
- `transform/tests/test_melt.sh` (60)
- `extract/tests/run_tests.sh` (70 files)
- `analyze/tests/run_tests.sh` (mawk and gawk)
- `tests/corpus/run.sh --golden`
- `python -m pytest`

`tests/corpus/run.sh --coverage` takes about 11 minutes.

## Next steps

0o. **2026-10-30: `batch` reuses a name's detection** (after 2.2.0). The
    first input of each name is detected; the rest try its strategy first
    and keep the result only if it is the same table (strategy, header,
    coverage no lower). 200 one-format inputs: 70 s -> 22 s through qd.
    Equivalence checked on 400 corpus inputs (376 identical, 24 refused by
    the rule and detected from scratch). Not done: reusing the detection
    of a hint row (its label is not a strategy name, so `-s` refuses it --
    those inputs are detected from scratch, correct but not faster).

0n. **2026-10-29: four readers qd was working around.** qd converted
    some outputs to TSV before filing them, and escaped quotes in its own
    tables, because provost read them badly. Fixed here instead:
    - **TSV quotes are data.** `tsv` deleted every `"` from every value
      after its split had already consumed the structural ones: `said
      "hi"` filed as `said hi`, a JSON column lost its quotes (the corpus
      golden `quo-tsv-json-column` had frozen exactly that). `""` inside a
      quoted field is now one quote, as in CSV.
    - **Nested JSON without jq.** `json`'s no-jq fallback read `"key":
      value` pairs a line at a time and stopped at the first nested value.
      `_json_walk` (`extract/lib/_helpers.sh`, mawk-safe awk) prints what
      the jq filters print — leaves under jq's paths for `json`, top-level
      keys with nested values as compact JSON for `jsonl` — and was
      checked byte for byte against jq on every JSON input in the corpus
      and samples (98 and 15). One difference, documented: jq 1.7 spells
      `1e3` as `1E+3`.
    - **JSON Lines after `#` comments.** `jsonl` skips comment lines in
      detection and extraction; a header line or two used to push the
      records out of its three-line window and the file read as aligned
      columns.
    - **`dc-results`** (`strategies/misc/`): the floor-plan viewer's
      results format (`!test` metadata over `test target value k=v`
      samples) written by mx export, iperf export-overlay, reckon
      --overlay, dcprobe and dcimport. A row per sample, its test's
      metadata on each. Claimed only by its `!test` lines: a `--no-meta`
      file is shaped like ordinary output, and stays with the generic
      parsers.

0m. **2026-10-29: `provost batch` and `--context-columns`**, for
    quarterdeck (`qd`), which drives the toolchain on a fleet and now
    files what comes back through provost: one capture per host, with
    `#% host=NAME ...` context.
    - **`batch`:** N inputs, a capture each (id, `source`, tag), ONE
      commit. `_ingest` is now `_ingest_parse` (no store writes, LLM
      templates aside) + `_ingest_store` (under the lock); `batch` runs the
      parse halves in parallel (`-j`) and the store halves in input order
      in one lock. 40 inputs: 13 s against 55 s as single captures, on 4
      CPUs; the lock is held about 50 ms an input, so a batch of several
      hundred inputs keeps other writers waiting past
      `PROVOST_LOCK_TIMEOUT` (30 s). Not built: committing in chunks for
      very large batches.
    - **`--context-columns`:** `key=value` prologue words as columns after
      `#` and `capture`; clash → `_NAME`; `unsorted` untouched; default off.
    - The results format and NDJSON after comments, listed here as worth
      doing next, are done: see 0n.

0l. **2026-10-28: provost as a test runner — every run viewable** (PR #88).
    Asked for in one session: a short help, search on git, a way to see
    every run, a capture id per row, a listen on commands, and an import
    that said every bundle was invalid.
    - **Import fixed:** `git bundle verify` refuses to run outside a git
      repository, so importing from an ordinary directory always failed. It
      now verifies in a scratch repository.
    - **`capture` column (store format 3):** every row is `#`, `capture`,
      `n`, then the data. Older stores are migrated on the next write from
      `provenance.tsv`; a data column already named `capture` keeps its name
      and the added one is `_capture`.
    - **Run files:** a capture in a controlled directory commits the
      directory's files too, tagged `files-<id>`, chained run to run, built
      with a scratch index (the store's tree never holds a copy).
      `.gitignore` honoured; `PROVOST_FILES_MAX_SIZE` (1 MiB) caps a file.
    - **Browse, all from git:** `show --capture ID` / `--at ID`,
      `source ID`, `prev` / `next` (move the restored store), `files`,
      `diff` (rows only A or only B filed, plus the files that changed),
      `search` (`git grep`: rows, `--output`, `--files`, `--at`).
    - **`listen CMD`:** a shell function per command in
      `~/.config/provost/listen.sh` running it through `run --show` (new:
      output shown and filed). Envoy's `watch`, dropped in the rename,
      comes back at shell level.
    - **Help:** `provost help` is 47 lines; `provost help advanced` is the
      full reference, ordered by how a capture is filed. Smoke checks every
      setting there, every command, and a 79-column width.
    - **Not built / worth doing next:** `diff` compares rows as multisets
      (row order and `n` ignored), which suits test results; a keyed diff
      (match rows on a column, report changed values) would suit tables
      like `df`. `listen` pipes the command, so it loses its terminal
      (no colour; Python buffers): running it under `script` would keep a
      pty. The run-files snapshot happens when the capture is filed, which
      at a terminal is in the background just after the command ends.

0k. **2026-10-27 (later): `--llm` measured through the real API, template
    repair on a miss, and a clean-up after extraction** (PR #87, stacked on
    #86; parts 4–7 of `docs/benchmark-2026-10-27-llm-templates-round4.md`).
    - **Where it stands (round 4, rated blind):**

      | | PASS | PARTIAL | FAIL | usable |
      |---|---:|---:|---:|---:|
      | default engine | 12 | 51 | 44 | 59% |
      | first contact, `learn` + clean-up | **87** | 18 | 2 | 98% |
      | the whole pipeline, second capture + clean-up | **83** | 22 | 2 | 98% |

      API cost: about five cents a tool on first contact; on a later
      capture, a call only when the template meets a kind of line it has
      not met (about one capture in three on round 4's second captures).
    - **First contact (`learn`):** before the clean-up, 66 / 30 / 11 for
      $5.20 (108 calls).
    - **Repair** (`template.py misses` / `repair`, wired into
      `_llm_template`): a stored template that meets a kind of line it has
      not met goes back to Claude once, with the captures it was written
      from (its `"examples"`), and the extension is kept only if it still
      reads them. Part 3 rerun: 73 / 28 / 6 against 65 / 32 / 10.
    - **Clean-up** (part 7): values keep to their cells (a newline inside a
      parser's value had made junk columns: all four first-contact
      FAILs); the lines a template sets aside that carry a word or a number
      go to `NAME.notes` instead of being dropped; the catch-all guard no
      longer counts skipped lines as lost. Measured +21 / +17 PASS, nothing
      rated lower. Not built: dropping empty columns (they are the tool's
      schema) or rule/header rows (none in 602 template tables).
    - **What is left, in order of how much it would lift:**
      1. **The judge, aimed at structure.** The ~20 PARTIALs left are a
         parent the template does not keep (an op tree, iseq headers,
         trunk members, taxonomy depth, caller/callee links), a record
         split across tables, a two-layout header half applied; plus, on
         later captures, a new kind of line a pattern matches and misreads
         (LXD rows as units). One call after `learn` and after `repair`,
         PASS or a list of fixes, fed back once.
      2. **Two gate rules still cost a FAIL each:** the `yaml` exemption
         (020 never reaches a template) and `_AM_FRAG_LINES` counting lines,
         not records (132 is held on every run).
      3. Then the library (plan step 5) and round 5, built and frozen before
         anything runs. Round 4 is spent for `--llm`.
    - Small: the melt should rename a template column colliding with the
      row id.

0j. **2026-10-27: `--llm` goes first, templates can be parsers (format 2),
    and round 4 is measured with templates** (`docs/plan-2026-10-27-near-100.md`
    is the plan; CHANGELOG has the detail).
    - **Why:** four rounds at 11–21% PASS on unseen output; the gate files
      27 of round 4's 44 FAILs at ≥95% coverage, so nothing behind it ever
      ran. A template written for one tool only has to fit that tool's next
      capture: no cross-tool generalisation needed.
    - **Done:** LLM-first hook in `_ingest` (before auto-multi/model on a
      held capture; before a generic parse the gate passed is trusted);
      `extract/llm/sandbox.py` runs a format-2 parser in a box;
      `PROVOST_LLM_TEMPLATE_DIRS`; `tests/benchmark/llm_round.sh`;
      `tests/benchmark/round4/llm-templates/` (107 format-1 templates by
      Claude helpers, with `.note`s on what format 1 could not express).
    - **Round 4 with templates** (`docs/benchmark-2026-10-27-llm-templates-round4.md`):
      format 1 alone **35 / 66 / 6**; with format-2 parsers for the 65
      inputs format 1 could not express, **86 / 18 / 3 (80% PASS, 97%
      usable) against the engine's 12 / 51 / 44**. No shape family under
      70% PASS. Of the 21 left, 4 are the catch-all guard declining a
      parser that skipped decoration, 1 the fragments rule on a one-line
      input, 1 the `yaml` exemption, 10 unrewritten format-1 templates
      PARTIAL on strict rule 3, 5 near-misses.
    - **Second capture** (part 3; `round4/variants/`, frozen; rated blind):
      the same stored templates on a never-seen second capture of each
      tool score **65 / 32 / 10 (61% PASS, 91% usable)**. Nearly every drop
      is a line kind the first capture never showed: the template is
      declined (5, falls back to the engine) or misses it (17); once a
      `skip` rule swallowed a diff while coverage read 100%.
    - **Not yet measured:** the first-contact rate through `learn` (two API
      attempts, no iteration).
    - **Next:**
      1. **Template repair on a miss:** a stored template's unread lines on
         a new capture go back to Claude to extend it (one call), kept only
         if it still reads the captures it was written from; record which
         captures each template has seen. Then rerun part 3.
      2. Skip lines audited (count + sample, judged), not counted as
         covered for free.
      3. The judge (step 3), then with the key the `learn` run, the library
         (step 5) and round 5.
      - **The key:** add it as `PROVOST_LLM_API_KEY` (a Claude Code
        environment keeps `ANTHROPIC_API_KEY` for its own sign-in).
      - Small: `_AM_FRAG_LINES` should count records; the melt should
        rename a template column colliding with the row id.

0i. **2026-10-26: `--llm`. Claude writes a parsing template for a tool once,
    and provost reuses it offline** (`extract/llm/`, LLM TEMPLATES in
    `provost help`).
    - **Tested** end to end against a fake API (`tests/fake_anthropic.py`).
    - **Not yet run against the real API:** the session's key was deleted.
    - **Next:**
      1. With a real key, run `--llm` over the 38 captures held in rounds
         2–4 and rate the templates.
      2. Grow `extract/llm/templates/` from the templates that prove good.
      3. Consider letting `--llm` re-check generic parses the gate passed.

0h. **2026-10-26: `--model` ships the LLM-trained trees, with a refitted
    arbiter.**
    - **Measured:** fresh test 136/150 (previous model + arbiter 133,
      engine 126); gold 242/300 (210, 193).
    - **Still opt-in**, and the corpus goldens are unchanged.
    - **Next:**
      - an end-to-end round 5 to measure `--model` on unseen captures;
      - consider making the model the default fallback for held captures.

0g. **2026-10-25: 297 format generators** (`ml/gen/`), **plus the
    LLM-trained trees measured on the full test** (`docs/gridnet-2026-10-23.md`).
    - **Generated data:** small gains for GridNet (+0.8 points), none for the
      trees.
    - **Trees on LLM labels + `synth.py`:** fresh test 131/150 (shipped
      130); gold 219/300 (194), hard lines 97 against 77.
    - **Decision needed:** ship these trees as the opt-in `--model`? It
      would need the arbiter refitted and the layout-model golden
      regenerated.
    - **Otherwise the layout model has plateaued** at about 83% of the
      teacher's splits on unseen families.

0f. **2026-10-23: GridNet, the self-learning model, was built and measured,
    and is not shipped** (`ml/train_grid.py`, `extract/model/gridnet.py`,
    `docs/gridnet-2026-10-23.md`).
    - **Result:** on 3,163 held-out lines it matches the LLM labels 79–81% of
      the time, against 82.9% for the trees. Averaging the two gives 83.5%.
      Too little data (about 3,000 small captures) for it to learn layout
      from scratch.
    - **Next:** have Claude write a few hundred format generators (correct
      labels by construction, about $10–30), then retrain both models and run
      the full 5-fold test plus the fresh test once. Needs a new
      `ANTHROPIC_API_KEY` in the environment.

0e. **2026-10-23: LLM teacher. Claude labelled the whole corpus (3,674 of
    3,705 kept; $24.48)** (`ml/llm/`, `ml/eval/llm-labels-2026-10-23.jsonl.gz`,
    `docs/llm-teacher-2026-10-23-pilot.md`).
    - **Teacher:** 147/150 on the fresh test lines (engine 126/150) and
      286/297 on gold, against a 97% human ceiling.
    - **Student:** the same tree model trained on these labels scores 132/150
      on the fresh test (shipped model 130/150) and 215/300 on gold (194).
      **The student is now the limit, not the labels.** The shipped model is
      unchanged.
    - **Next:**
      1. A character-grid model that learns its own features from the whole
         capture, trained on the LLM labels (numpy/onnxruntime at capture
         time, as an optional extra).
      2. Then a round 5 to measure it.
      3. Review a sample of the 8,931 lines where the LLM and the engine
         differ (`ml/llm/score.py --sheet`); the pilot's 102 lines are in
         `ml/eval/llm-pilot-review-2026-10-23.md`.
      4. **Rotate the API key the user pasted into chat on 2026-10-23.**

0d. **2026-10-23: the model now works inside auto-multi (per part, and
    with its own sections) and arbitrates with the engine per line.**
    - **Result:** 0 extra rescues on rounds 2 and 3 (22 held captures). The
      gate rejects every model section there, for dropped prose lines or
      headerless tables.
    - **Where the value is instead: captures the engine files WRONG at
      high coverage.** One constructed example: a summary over a table,
      with no blank line between them, filed as whole-line text cells; the
      model's sections are exactly right.
    - **Next:**
      - the model as a second opinion on FILED generic parses (hold or
        replace when it disagrees strongly);
      - a round 5 to measure that honestly.

0c. **2026-10-22: the layout model is in provost, opt-in (`--model`,
    `PROVOST_MODEL=1`, default off).**
    - **Where:** the runtime is `extract/model/` (stdlib; the trees are
      `layout-model.json.gz`, rebuilt by `ml/export_model.py`), behind the
      explicit-only strategy `layout-model`.
    - **When it runs:** only for a capture the gate still holds after
      auto-multi. Its table is filed only if it passes the same gate.
    - **Round 4, measured once:** 15 held captures became 14 held and 1 filed
      (PARTIAL); no wrong table was filed. Almost everything still held is a
      mixed multi-section report, which the model declines by design.
    - **Next:** apply the model per segment inside auto-multi (the parts
      the engine can't read), and use `ml/arbiter.py` where both produce a
      table.
    - **Round 4 is now spent** for this change too; the next honest
      measurement needs a round 5.
    - **Ceiling and arbiter:** the labeller-agreement ceiling is about 97%.
      The arbiter scores 88.7% on the fresh test (model 86.7%, engine 84%).
      `ml/decode.py` became `extract/model/decode.py`.

0b. **2026-10-22: a small learned layout model, steps 1-2 (`ml/`, dev-only,
    nothing ships).** Write-up: `docs/model-2026-10-22-layout-steps1-2.md`.
    - **Training set:** 2,831 corpus files (18,231 lines) labelled from the
      goldens with line roles and field starts, plus a 4,000-document
      synthetic generator. Stdlib tests run in CI (`quick-checks`).
    - **Best model:** LightGBM trees trained on the corpus. On held-out tool
      families they split 77% of lines exactly right, against 54% for
      splitting on spaces (about 85% after a hand audit of label errors).
      Roles: 87% (95% counting row≈kv). Size: 3.3 MB gzipped.
    - **LayoutNet** (a 53k-parameter CNN+GRU, 100 KB) reaches 69%: smaller,
      not better. Synthetic data barely transfers to real tools.
    - **The labels are now the limit:** about a third of the disagreements are
      provost's own golden mistakes.
    - **Measured against 300 hand-labelled lines** (`ml/eval/gold-*.jsonl`,
      scored out of fold by `ml/crossval.py`):
      - the improved tree model is right on 62% of all lines and 77% of
        random lines;
      - the engine scores 64% and 80%;
      - one or the other is right on 85% of random lines.
      - The model uses the new features plus `--clean 0.05 --fix-labels`;
        `train_baseline.py --final` builds it.
    - **Fresh test (150 random lines, scored once; `ml/eval/test-*.jsonl`):**
      model 86.0%, engine 84.0%, so the two are level. One or the other is
      right on 91%.
      - The large dev-set gains were mostly a selection effect: the "hard"
        lines were picked where the first model was wrong.
      - On the 1,755 maintainer-approved lines the model matches 85%.
      - Don't expect it to replace the engine. Step 3 should use it only
        where the gate holds the engine's parse.
    - **Step 3 (next):**
      - a pure-Python tree evaluator, so there is no new dependency;
      - wire it behind `PROVOST_MODEL` (off by default), only for captures the
        gate would hold, and accept its parse only if it passes the gate;
      - measure once on round 4. `tests/benchmark/` was never read by `ml/`.
    - Reproduce: `ml/README.md`.

0a. **2026-10-20, PR #79 (unreleased; would be 2.3.0):**
    - **Round 4:** 107 unseen inputs on the 2.2.0 engine.
      - Default mode: 11% PASS, 48% PARTIAL, 41% FAIL (59% usable).
      - `--multi`: 71% usable.
    - **Automatic `--multi` fallback** (`PROVOST_AUTO_MULTI=1`): before the
      gate holds a weak parse, segment it and file the parts if every part
      passes the gate.
    - **Measured once on round 4:** 2 rescues, 1 wrong table filed, 6 missed
      rescues. That is a small net gain.
    - **Next:** loosen the guards to recover more of the 8 possible rescues,
      tighten the per-part check that let 048 through, then measure on a
      round 5.

0. **Done 2026-10-20 (PR #77), not yet released.**
   - Six engine defects from round 3 are fixed: no-output fallback, tsv
     truncation, duplicate names losing values, fixed-width cutting digits,
     the invented gnu-version field, and the dot-leader near-miss.
   - The **quality gate** is in: likely-wrong generic parses (coverage < 80 or
     consistency < 70) go to triage. On the rated sets it holds 18 of 48 FAILs
     and 0 of 57 PASSes. Tune it with `PROVOST_MIN_COVERAGE` /
     `PROVOST_MIN_CONSISTENCY`, or turn it off with 0.
   - Release as 2.2.0 together with the 2026-10-16 work.

1. **Rethink the approach before another fix round.** Two rounds of
   pattern-level fixes, each developed against new examples, moved unseen
   FAIL by only 1–3 points while seen sets improved a lot. More heuristics in
   the same style will probably fit what we can see again. Options worth
   weighing:
   - Use `--multi` segmentation by default when coverage or consistency is
     weak. `--multi` was better on 19 round-3 inputs.
   - Make the parse-quality signals decide more often, not just veto.
   - Narrow the claim: report low confidence and route to triage instead of
     committing a wrong table. Today every input clears the commit
     threshold, but a third are wrong.
2. ~~Engine bugs found by round 3~~ — fixed 2026-10-20 (see 0). Originally:
   - `java -XX:+PrintFlagsFinal`-style input gives no output at all.
   - `tsv` truncates rows to the first row's width while coverage reads 100.
   - duplicate column names lose values in the melt.
   - `gnu-version` emits a field that is not in the input.
   - a bespoke parser claims near-miss input at under 31% coverage and is not
     held.
3. **Round 4**, built before the next fix round, to measure it.
4. **Release 2.2.0** when PR #76 lands, following the 2.1.0 steps (CHANGELOG
   2026-10-16 release entry). Publishing needs a person: this session type
   cannot create GitHub releases.
