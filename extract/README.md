# provost/extract — the extract engine

This directory holds provost's extract engine + all strategies. `provost` runs it
in-process (via the `--emit-meta` contract) to auto-detect the format of captured
output.

The engine sources cross-suite shared libraries (version, progress, pager, …)
from its sibling `../lib` — i.e. **`provost/lib/`**.

**This is first-party provost code — edit it here.** The tree was originally
imported from the Envoy suite's `EnvoyExtract/` project, but it is now maintained
in this repo directly; there is no live upstream sync. Add a new format-detection
strategy under `strategies/` with its sample + golden fixtures, then run the suite:

```bash
bash extract/tests/run_tests.sh     # strategy + engine suite
```

`tools/new_strategy.sh` and `tools/review_strategy.sh` scaffold and check a new
strategy.

## Layout

| Path | Purpose |
|---|---|
| `envoy-extract` | engine entry point (invoked internally by `provost`) |
| `lib/` | engine libraries (dispatch, format, postprocess, …) |
| `strategies/` | the 257 format-detection strategies, in 15 category dirs (111 generic format parsers in `delimited/` + `structured/`) |
| `tools/` | strategy-authoring helpers (`new_strategy.sh`, `review_strategy.sh`) |
| `samples/` | sample inputs used by the strategy tests |
| `tests/` | the strategy + engine test suite (`bash tests/run_tests.sh`) |
| `../lib/` (`provost/lib/`) | shared suite libs the engine sources via `../lib` |

## Strategy count

257 strategy files (`ls strategies/*/*.sh | wc -l`): delimited 86, system 57,
network 31, structured 25, security 10, filesystem 8, build 7, misc 7,
database 6, hardware 6, packages 6, scientific 5, cloud 1, container 1,
profiling 1. Re-count after adding or removing one — the number is only true
when it is counted. Every strategy has a `## Sample:` file under `samples/`
and a golden under `tests/golden/`; `tests/verify_strategy_outputs.sh`
fails (rather than skips) when either is missing.

## Writing a strategy: keep detection cheap

Detection runs EVERY eligible strategy's `strategy_detect` on every capture
(see "Candidate ranking" below) — so a slow detector taxes every capture, not
just the ones it wins. Equal priorities are ordered by strategy name (byte
order), never by the category folder. Use the fast helpers from
`lib/_helpers.sh` instead of the slow idioms:

- `_fr_lines "$text"; for l in "${_FR_LINES[@]}"` rather than
  `while IFS= read -r l … done <<< "$text"` (a here-string is read one byte
  per syscall);
- `_fr_tok "$l"; a=("${_FR_TOK[@]}")` rather than `read -ra a <<< "$l"`;
- `_fr_modal` for a modal count — never a nested all-pairs loop;
- `[[ "$l" != *[![:space:]]* ]]` for a blank-line test, and no `$(…)` per line.

When acceptance needs a literal the input must contain, test the whole text for
it first (`[[ "$text" == *LIT* ]] || return 1`) — see the `PREFILTER (exact)`
comments in e.g. `strategies/delimited/box-table.sh`.

### Very large inputs

Above `_FR_SAMPLE_BYTES` (32 KB) detectors see a bounded SAMPLE of the input
(the first 120 / last 40 whole lines, byte-capped; JSON/XML documents are
never cut), and a strategy that accepts the sample is re-run on the full text,
which alone decides acceptance and confidence (`lib/_discovery.sh`). So a
detector must never ACCEPT a sample it would reject in full — it cannot, the
full text re-decides — but it can falsely REJECT when its evidence lies only
in the middle of a huge input; prefer evidence the head carries.

Above `_FR_BIG_BYTES` the hot generic parsers (`aligned-columns`, `csv`,
`syslog`, `equals`, `json-array`) and the engine's own passes switch to awk
twins that are byte-identical to their bash loops, and above `_FR_LANE_BYTES`
the result stays in a file to the end (the FILE LANE). Setting a knob to 0
forces its route on any input — `tests/test_big_input_paths.sh` and the
corpus proofs compare every route with the plain bash one. A new twin must
follow the same rule: same bytes, proven by forcing it over the corpus.

Values keep their spaces: sanitise field NAMES with `_clean_field`, and pass
values through `_clean_value` (never replace a value's spaces with `_`).

## Candidate ranking

`run_auto_strategies` (lib/_discovery.sh) picks the winner in two phases:

1. **Detect.** A `hints.tsv` row, when one matches, is still tried first. Then
   every eligible strategy's `strategy_detect` runs (deprecated, `--generic`
   and `--min-confidence` filters apply), and each one that fires becomes a
   candidate carrying its `_STRATEGY_CONFIDENCE`.
2. **Extract, best first.** Candidates are sorted by confidence (high first),
   then priority (low number first), then strategy name (byte order,
   `LC_ALL=C`), and tried in that order: detect is re-run to restore the
   strategy's detect-time state, then extract. A candidate whose extract is
   empty, or that trips the truncation guard, yields to the next one, so the
   winner always has output. `--max-strategies N` / `--first-match` stop after
   N / 1 candidates produced output.

`--rank priority` (or `MFE_RANK=priority`) restores the historical single pass:
the first strategy in priority order whose detect passes and whose extract is
non-empty wins, and confidence is only compared to thresholds. `--strategy` and
`--replay` pin their own strategy set and always use that single pass. `--multi`
groups blocks by the same ranking (`_multi_detect_name` in lib/_dispatch.sh:
highest-confidence detector, ties by priority then name); being detect-only it
cannot fall through an empty extract, which the per-group extract then does.

## Confidence rubric

Confidence is a **ranking** signal: it says how conclusive a detector's
evidence is, on one scale shared by every strategy. Priority is the
tie-breaker, i.e. *specificity* — when two strategies have equally conclusive
evidence, the more specific one (lower priority number) wins. Set
`_STRATEGY_CONFIDENCE` in `strategy_detect` by tier:

| Tier | Confidence | What earns it | Strategies |
|---|---|---|---|
| Bespoke, strong signature | **92** | a tool-unique literal or layout (banner, header, fixed field set) only that tool prints | every per-tool strategy outside `delimited/` + `structured/`, unless demoted below |
| Grammar | **85** | the whole input validates against a formal grammar, or a strict dialect of one | `json`, `json-array`, `jsonl`, `yaml`, `toml`, `xml`, `csv`, `tsv`, `har`; dialects that must outrank their grammar: `quoted-fields` (CSV), `dns-records` / `columnar-specs` (TSV-shaped), `colon-pairs` (YAML-shaped), `kv-pairs` (CSV-shaped); `pipe-table` / `bracket-log` at their strongest |
| Format-specific generic | **70–85**, default **80** | a distinctive syntax (box drawing, psql rules, dot leaders, tree glyphs, `KEY=VALUE` blocks, blank-line records …) | the other `delimited/` + `structured/` parsers at 80; `equals` 75 when ≥ 90% of lines are tight `KEY=VALUE`. Weak-signature bespoke strategies whose detector is a shape heuristic rather than a tool-unique literal sit here too (`pkg-config`, `git-log-graph`: 80) |
| General structure | **55–69**, scaled | a shape any tabular or kv output has | `aligned-columns` 60–69 (the 40–75 header/consistency score mapped linearly); `colons` 55–60 by the share of `label: value` lines (40% → 55, 100% → 60); `numeric-lead-records` 60 |
| Catch-all | **≤ 60 (50–55)**, scaled | line structure only | `equals` (weak) 50–55 by the share of assignment lines; `line-records` 50–55 by the share of lines at the modal token count (60% → 50, 100% → 55), 50 for a one-token-per-line list, 51 for a single line; `text-lines` **50** — ranks last, still clears provost's default commit threshold (50) |

Rules that keep the tiers honest:

- A score must be **evidence-based**: scale it by a measured share (lines that
  match, column consistency) when the detector already computes one, and never
  hand out a constant above the tier the evidence supports.
- **Nothing below 50 on a winning parse.** Under ranking a sub-50 score ranks
  below `text-lines`, which then claims (and files) the input anyway — so a
  "stay under provost's threshold" score only hands the input to a worse parse.
  (`colons` and weak `equals` were a flat 35 for that reason before ranking.)
- `aligned-columns` never drops below 60 on a table it detects: a header with
  consistent columns beats every catch-all and loose kv shape, and loses to any
  format-specific syntax.
- Ties are resolved by priority, so within a tier keep the priority order
  meaningful (more specific = lower number).
- Calibrate against the corpus: the confidence-ranked winner must pass the
  manifest tidy check, and match the golden unless demonstrably better, on the
  full and the `--generic` candidate sets (`tests/corpus/run.sh --golden`).
  Holdout and benchmark inputs are held-out checks — never fit on them.
