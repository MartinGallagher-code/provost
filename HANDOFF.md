# Handoff — provost

The history that used to live here (2026-07 → 2026-09-16, ~100 KB) is in git:
`git show 9f9d7c0:HANDOFF.md`. `CHANGELOG.md` has the dated detail.

## Present state (2026-10-22)

**provost 2.2.0 is prepared** (`VERSION`, man header, CHANGELOG release entry).
PyPI serves 2.1.0 (published 2026-10-16) until a `v2.2.0` GitHub release is
published. 2.1.0 was the first release with the rename, store format 2, line
coverage and the 2026-10-14 parser work. 2.2.0 adds the 2026-10-16 and
2026-10-20 work: the quality gate, the engine fixes, and removal of the legacy
names.

provost is one Bash entry point (`provost`) over:
- the extract engine (`extract/provost-extract`, 265 strategies, ~116 generic)
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
- Captures and `rm` are refused while `provost restore <id>` has a capture out.
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
- `tests/smoke.sh` (208)
- `transform/tests/test_melt.sh` (54)
- `extract/tests/run_tests.sh` (70 files)
- `analyze/tests/run_tests.sh` (mawk and gawk)
- `tests/corpus/run.sh --golden`
- `python -m pytest`

`tests/corpus/run.sh --coverage` takes about 11 minutes.

## Next steps

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
