# Handoff — glean

## Status: Standalone; generic-first extraction refactor landed (2026-07-09)

`glean` is the single-binary tool proposed in
[docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md)
to replace the three-binary `envoy-*` suite. It lives in its own repository and
is **fully self-contained**: the entry point resolves its engines from its own
directory (`GLEAN_ROOT`), so it runs with no external dependencies.

> **2026-07-06 — cut from Envoy.** The `extract/`, `analyze/`, `transform/`, and
> `lib/` trees are first-party glean code, maintained in this repo directly.
> Edit them in place. Any future re-integration with Envoy is a deliberate
> manual merge, not a routine sync.

## The 2026-07-09 refactor — generic-first extraction

The project goal is to process as many inputs as possible with as few
instructions as possible, generalize to unseen-but-similar inputs, and hold
bespoke parser code to (ideally) zero. The extraction layer was restructured
around that:

1. **`--generic` is directory-based, not tag-based.** A strategy is generic iff
   it lives in `extract/strategies/delimited/` or `extract/strategies/structured/`
   (28 files). The old `## Technique: yes` header tag had drifted onto ~145
   per-tool parsers, silently inflating the "generic coverage" metric; the tag
   is gone and the engine no longer reads it.
2. **Declarative hints table** — `extract/hints.tsv`. One TAB-separated row
   (tool, match-type, structural signature, target strategy) routes a
   recognized tool's output to an existing generic strategy, replacing a
   per-tool parser script. The engine consults it before auto-detection
   (`--no-hints` disables; `MFE_HINTS_FILE` overrides the path). The matched
   row's tool name is reported via `_STRATEGY_REPORT_NAME`, so dataset identity
   survives without bespoke code. Signatures must be structural (format shape),
   never sample literals — they are expected to match unseen output of the
   same tool. 46 rows currently cover 50 corpus inputs.
3. **218 bespoke strategies deleted** (375 → 156 strategy files), with their
   samples, goldens, and per-strategy tests. Deletion criterion: every corpus
   input the strategy won stays manifest-tidy via a generic parser or hint row.
   The 128 surviving bespokes are each the proven full-mode winner of at least
   one corpus input, or qualitatively better than the generic parse
   (`free`, `docker-ps` — the smoke test guards their column quality).
4. **Coverage is three-tier and honest** (`tests/corpus/COVERAGE.md`):
   ✅ 836 generic auto-detected · ✅ʰ 50 hint-routed · ✅ᵇ 153 bespoke ·
   ⏳ 1 (`traceroute6`; its earlier "covered" entry was stale). Total
   1039/1040. Goldens are generic-mode output: 119 old goldens were deleted
   because they had been produced by pseudo-generic per-tool parsers — those
   inputs are now honestly ✅ᵇ (no golden), same as every other bespoke tool.
5. **Detection-order fixes** in full mode: `git-log-stat` (p13) runs before
   `git-log` and absorbs `git show --stat` (the separate `git-show-stat`
   strategy was deleted); `nmap-sn` (p14) runs before `nmap` and declines
   outputs containing a PORT table; `bundle-outdated`/`semanage-boolean` (p12)
   run before the grabby `pkg-config`.
6. **Dead weight removed**: orphaned analyze `browse`/`dashboard`/`mdx`/
   `help_overlay` tests (surfaces glean doesn't ship — the raw
   `analyze/tests/run_tests.sh` is now green and CI runs it unfiltered), and
   7 unreferenced `lib/envoy_*.sh` helpers (`common`, `format`, `humanize`,
   `spinner`, `status`, `tasklist`, `exit_codes`).

### How to extend coverage now (in order of preference)

1. **Generic parser tweak** — if a new tool's output is close to a covered
   format, improve the generic parser (they carry ~80% of the corpus;
   `aligned-columns` alone covers ~340 inputs).
2. **Hint row** — if a generic strategy tidies the output when forced
   (`envoy-extract --strategy <name> <file>`) but auto-detection picks wrong,
   add one row to `extract/hints.tsv`. Validate with
   `tests/corpus/run.sh --golden` (catches signature misfires on other tools).
3. **Bespoke strategy** — last resort, only for genuinely idiosyncratic
   formats. It must win its corpus input in full mode (mind `## Priority`
   vs. grabbier strategies).

## What works now

The default verb plus `ls` / `show` / `rm` / `stats` / `triage` / `doctor` / `help`, and
the git-core verbs `run` / `log` / `restore` / `source` / `export` / `import` /
`control`:

```bash
free -m        | ./glean            # captures in the BACKGROUND by default (async)
free -m        | ./glean --sync     # foreground: prints the resulting dataset + #N
docker stats   | ./glean
./glean run df -h                   # capture a command's output AS A COMMIT
./glean ls                          # list datasets
./glean show free                   # present a dataset as a tidy table
./glean stats free                  # statistics via the analyze engine
./glean source 5                    # the original input behind row #5
./glean triage                      # low-confidence / unmatched bucket (raw input decoded)
./glean show unsorted               # same bucket as a table; base64 raw decoded to text
./glean rm free                     # delete a dataset + its captures (purge is default)
./glean rm -f --no-purge free       # delete the dataset but keep the source captures
./glean doctor                      # engine + store check
```

## Architecture

### Extract (the default verb)
Runs the **extract engine** (`extract/envoy-extract`) via its
`--emit-meta -f tsv --max-strategies 1` contract, classifies by the winning
strategy + confidence, melts the wide `entry<N>.<field>` output to **one row per
record**, and appends it to a per-type dataset. Detection order per capture:
hint rows (`extract/hints.tsv`) → strategies by ascending `## Priority`
(confidence is mainly a threshold gate). The engine sources the shared libs at
`lib/` (its `../lib`).

### Transform (`transform/melt.sh`)
The tidy melt (`_core_melt_tidy`) and schema-union helpers (`_core_union_header`,
`_core_align_rows`) live here, first-party. `run` and pipe-`inject` share one
`_ingest` pipeline (extract → classify → melt → store → record capture → commit).
Unit test: `bash transform/tests/test_melt.sh`.

### Git core
The store is a **git repo** (`$GLEAN_WORKSPACE`). Every capture is one commit,
tagged `capture-<id>`; each writes `captures/<id>/{meta.tsv,output.txt}` alongside
the dataset change. `glean log` lists captures; `glean restore <id|latest>` brings
one back up. This is a simplified linear-history model (proposal 0001 §7).

### Store model
- **Global by default** — `$GLEAN_HOME` or `~/.glean`; capture from anywhere.
  `GLEAN_WORKSPACE` explicit override wins (tests use it).
- **Per-row provenance** — every dataset row has a globally-unique visible `#N`
  index; `glean source <#N>` returns the exact captured input that produced it.
- **Multi-user** — `mkdir` store lock + double-checked `git init`; verified under
  8-way concurrency.
- **Controlled dirs** — `glean control [<dir>]` makes `<dir>` its own instance;
  resolution walks up from CWD (override → controlled → global).
- **Export / import** — `glean export` writes a portable `git bundle`;
  `glean import` reconstitutes it elsewhere with provenance intact.

### Analyze (`analyze/`)
`glean stats <dataset> [args]` runs the analyze engine over a dataset's TSV.
The `browse`/`dashboard`/`pipeline` surfaces are intentionally absent, and
their orphaned tests were deleted — the raw analyze suite runs green.

### Schema reconciliation
`_store_append` unions a differing-column same-type capture into the base dataset
when column overlap ≥ `GLEAN_RECONCILE_OVERLAP` (default 60%), blank-filling both
sides; below the threshold it splits to a numbered variant (`free.v2`).

## Next steps

1. **Audit the 62 regenerated goldens for parse quality.** The corpus manifest
   checks shape (row/col counts), not content quality. The hint-routed tools'
   goldens changed parser; a row-by-row skim of `tests/corpus/expected/` diffs
   in this branch would confirm none traded named columns for `c1..cN` mush.
   (`free`/`docker-ps` were caught by the smoke test and kept bespoke; others
   have no such guard.)
2. **Whittle the ✅ᵇ tail (153 inputs, 128 strategies).** Each survivor either
   needs a generic-parser feature (multi-line records, transpose+key-slug,
   number+unit merge — see `docs/columnar-specs-engine.md` for the data-driven
   columnar precedent) or is genuinely idiosyncratic. New engine features beat
   new bespokes.
3. **`traceroute6`** — the one ⏳: the columnar-specs `traceroute` spec drops
   `* * *` timeout hops (manifest wants them as rows). Needs a spec/engine
   tweak for placeholder rows.
4. **Held-out generalization corpus** — second samples per tool (other
   versions, locales, flag combinations) scored only on "does a generic parser
   or hint tidy it", to measure generalization instead of memorization.
5. Optional: rename the internal `envoy-*` binaries / `envoy_*.sh` libs to
   `glean`-native names (large, internals-only).

## Tests

```bash
bash tests/smoke.sh                 # end-to-end (49 checks)          [CI]
bash transform/tests/test_melt.sh   # transform unit (8 checks)       [CI]
bash extract/tests/run_tests.sh     # extract strategy + engine suite [CI: 63/63 files]
ENVOY_ANALYZE_SUPPRESS_AWK_WARNING=1 bash analyze/tests/run_tests.sh  # [CI, green raw]
bash tests/corpus/run.sh --golden   # corpus regression (886 goldens, non-CI)
bash tests/corpus/run.sh --coverage # regenerates COVERAGE.md
```

`smoke.sh` is hermetic — it clears the caller's `GLEAN_*` env (notably
`GLEAN_HOME`) so a stale `~/.glean/extract` engine can't shadow the bundled one
and skew classification. If a real `glean` run misclassifies, check
`glean doctor`: it warns when the extract engine came from a `GLEAN_HOME`
override rather than the bundled tree.
