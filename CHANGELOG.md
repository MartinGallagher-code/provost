# glean — Changelog

## 2026-07-06 — broaden the corpus to 34 tools (30 tidy, 29 via generic parsers)
- Expanded `tests/corpus/` from 22 to **34 common Linux tools**, including varied
  output for the same tool (`free -h`, `df -i`, `ps -ef`): added `ps-ef`, `lsof`,
  `du-h`, `lsusb`, `free-h`, `df-i`, `os-release`, `ethtool`, `id`, `uname-a`,
  `journalctl`, `lspci`.
- **29 of the new+old set tidy via a generic parser** with no new strategy needed
  (the `aligned-columns` header/headerless/two-line modes and `bracket-log` carry
  most of them); `uptime` stays bespoke. Coverage: **30 / 34** — see
  `tests/corpus/COVERAGE.md` (regenerate with `run.sh --coverage`).
- Four documented gaps for later: `du-h` (tab-separated headerless 2-col stolen by
  `tsv`), `id` / `uname-a` (single-line freeform), `lspci` (its bespoke strategy
  emits only 1 of N devices).
- `run.sh` coverage view now also melts full mode so it can mark bespoke-only
  coverage (✅ᵇ); fixed a stray `local` outside a function.
- No engine/strategy changes this batch (inputs + manifest + harness only); smoke
  33/33, golden regression 29/29.
- Files: `tests/corpus/inputs/*` (+12), `tests/corpus/expected.tsv`,
  `tests/corpus/expected/*`, `tests/corpus/run.sh`, `tests/corpus/COVERAGE.md`,
  `tests/corpus/README.md`.

## 2026-07-06 — full tidy coverage of the 22-tool corpus (21 generic + 1 bespoke)
- Closed the last corpus gaps; all 22 common tools now come out tidy — **21 via
  a generic parser, `uptime` via its small bespoke strategy** (a single-line
  prose status no generic parser fits; the accepted exception).
- `aligned-columns`: added a **two-line-header** mode (group row + field row, for
  `vmstat`) and a **`total <n>` preamble skip** (for `ls -l`).
- New generic **`bracket-log`** parser (`extract/strategies/logging/bracket-log.sh`)
  for `[tag] message` log lines — tidies `dmesg` (and the kernel ring buffer /
  many app logs) into (timestamp, message) rows. Ships a sample + golden.
- The 21 generic tools are covered by 7 parsers total: `aligned-columns`,
  `bracket-log`, `yaml`, `key-value`, `equals`, `colons`, `indented-hierarchy`.
- `run.sh --coverage` / `COVERAGE.md` now distinguish ✅ generic vs ✅ᵇ bespoke
  coverage. Full extract suite 219/219; smoke 33/33; melt 8/8; golden regression
  21/21.
- Files: `extract/strategies/delimited/aligned-columns.sh`,
  `extract/strategies/logging/bracket-log.sh`,
  `extract/samples/bracket-log/dmesg.txt`, `extract/tests/golden/bracket-log.txt`,
  `tests/corpus/*`.

## 2026-07-06 — generic tidy coverage 13 → 18/22 (headerless tables + tighter structured parsers)
- **Tightened the over-eager structured parsers** so they stop stealing tabular
  input from the columnar parser: `json` now requires the input to *close* with
  `}`/`]` (rejects `dmesg`'s `[ts] msg`), `yaml` requires a strong majority of
  YAML-shaped lines (rejects `free`/`sensors`), and `csv` ignores commas inside
  parentheses (rejects `mount` options like `(rw,nosuid,nodev)`).
- **Added a guarded headerless mode to `aligned-columns`** (now the generic
  parser for `who`, `mount`, `ip route`): when the first line already looks like
  data (has a digit-bearing token) it synthesises `c1..cN` columns instead of
  eating a data row as the header. Requires ≥3 consistent columns so it can't
  swallow key/value input.
- Net: generic-only tidy coverage **13 → 18 of 22** (`ss`, `lsblk`, `docker-ps`,
  `mount`, `who`, `ip route`, `free`, `sensors` added). Full extract suite stays
  **219/219**; smoke 33/33, melt 8/8.
- **Coverage is now queryable**: `tests/corpus/run.sh --coverage` generates
  `tests/corpus/COVERAGE.md`, a ✅/⏳ table of which tools tidy via a generic
  parser. Remaining gaps: `dmesg`, `ls -l`, `vmstat`, `uptime` (each needs
  targeted handling — see the corpus README).
- Files: `extract/strategies/structured/{json,yaml,csv}.sh`,
  `extract/strategies/delimited/aligned-columns.sh`, `tests/corpus/*`.

## 2026-07-06 — tidy-coverage corpus + generic columnar parser (fewer strategies)
- Start moving toward the design goal of tidying common tool outputs with a
  **minimum of strategies** (the ~12 generic parsers), rather than one bespoke
  strategy per tool.
- **New corpus + batch harness** under `tests/corpus/`: 22 common Linux tool
  outputs (`inputs/`), a correctness manifest (`expected.tsv`: per-tool expected
  tidy shape), frozen golden outputs for covered tools (`expected/`), and one
  script `run.sh` that runs every input through the engine in full and
  `--generic` modes, melts it, and checks tidiness. Modes: report / `--golden`
  (regression) / `--update-golden`.
- **Rewrote `aligned-columns` detection** (the generic whitespace-columnar
  parser) from a brittle header-shape regex to structural column-consistency
  with graded confidence, and raised its precedence (priority 70 → 55) so it
  wins tabular input over the key/value parsers (`colons`/`equals`) that were
  collapsing tables to a single row. Generic-only tidy coverage went **7 → 13
  of 22** (now: ps, df, top, iostat, netstat, ss, lsblk, docker-ps, systemctl +
  the key/value set). Full extract suite stays green (219/219); smoke 33/33,
  melt 8/8.
- Documented the tested tools and the 9 remaining gaps (over-eager
  `json`/`yaml`/`csv`; headerless tables; irregular structure) in
  `tests/corpus/README.md`.
- Files: `extract/strategies/delimited/aligned-columns.sh`, `tests/corpus/*`.

## 2026-07-06 — cut the cord to Envoy: extract/analyze/transform/lib are now first-party
- glean is now a **fully standalone** project with no live tie to Envoy. The
  `extract/`, `analyze/`, `transform/`, and `lib/` trees — originally imported
  from the Envoy suite — are now maintained here directly as first-party code.
  Extract strategies and engine changes are made in place, without regard to
  upstream Envoy; any future re-integration is a deliberate manual merge.
- **Removed the vendoring apparatus:** deleted `tools/sync-extract.sh`,
  `tools/sync-analyze.sh`, `tools/sync-melt.sh` (emptying `tools/`), and the
  `extract/VENDOR.json` / `analyze/VENDOR.json` provenance files. The original
  import points are preserved in git history and in this log (extract from
  `EnvoyExtract` @ `81bcb18`, analyze from `EnvoyAnalyze` @ `533bec8`, transform
  from `EnvoyCapture` @ `8639a6ef`).
- **`glean`:** removed the sibling-Envoy runtime fallbacks — `_find_engine` and
  `_find_analyze` no longer walk up looking for `EnvoyExtract/`/`EnvoyAnalyze/` or
  a `command -v envoy-*` on PATH, and `_source_transform` no longer falls back to
  a sibling `EnvoyCapture/lib/_core.sh`. The engines resolve only from this tree
  (`GLEAN_ROOT/extract`, `/analyze`, `/transform`) with a `GLEAN_HOME` override.
  Reworded the "not found" errors and `doctor` note that pointed at the deleted
  sync scripts to point at the expected in-repo paths.
- **Docs flipped from "vendored, do not hand-edit" to first-party:** rewrote the
  repository-layout / policy sections of `CLAUDE.md`, `README.md`, `HANDOFF.md`,
  and `extract/README.md`; updated the `transform/melt.sh` header (kept the
  original-import provenance line, dropped the "VENDORED / re-import" framing).
  Retitled a couple of stale "vendored" comments in `install.sh` / `tests/smoke.sh`.
- Historical CHANGELOG and `docs/0001` entries that describe the earlier vendored
  model are left intact (dated record).
- Verified green: smoke 33/33, transform 8/8, extract suite, analyze suite.
- Files: `glean`, `transform/melt.sh`, `CLAUDE.md`, `README.md`, `HANDOFF.md`,
  `extract/README.md`, `install.sh`, `tests/smoke.sh`; removed `tools/sync-*.sh`,
  `extract/VENDOR.json`, `analyze/VENDOR.json`.

## 2026-07-06 — drop Phase-5 framing (out of scope for the standalone repo)
- Phase 5 of proposal 0001 was "retire Envoy" — hard-cut the `Envoy*` trees in
  place in the monorepo. The standalone-repo split (2026-07-05) superseded that:
  `glean`'s vendored `extract/`/`analyze/`/`transform/`/`lib/` trees are already
  canonical here, and removing the upstream `Envoy*` trees is now a task in the
  Envoy monorepo, not this repo. Removed the stale "until the Phase-5 hard cut" /
  "retired at the Phase-5 cut" caveats that framed pending in-repo work.
- `HANDOFF.md`: dropped Phase 5 from "Next steps"; retitled the standalone-repo
  section; clarified the vendored trees are canonical here.
- `docs/0001-rename-and-simplification.md`: marked Phase 5 superseded by the split;
  reworded the Phase-2 re-sync caveat.
- `glean`, `tools/sync-{extract,analyze,melt}.sh`, `extract/README.md`: reworded
  engine/transform-locator and sync-script comments to describe the trees as
  canonical and the sync scripts as upstream re-vendoring (not "retired at Phase 5").
- Regenerated the `note` text in `extract/VENDOR.json` and `analyze/VENDOR.json`
  to match the updated sync scripts.
- Historical CHANGELOG entries below that mention Phase 5 are left intact (dated
  record). Verified green: smoke 33/33, transform 8/8.
- Files: `HANDOFF.md`, `docs/0001-rename-and-simplification.md`, `glean`,
  `tools/sync-extract.sh`, `tools/sync-analyze.sh`, `tools/sync-melt.sh`,
  `extract/README.md`, `extract/VENDOR.json`, `analyze/VENDOR.json`.

## 2026-07-05 — extracted to standalone repository (glean split from envoy)
- glean is now its own repository. The self-contained `glean/` tree was extracted
  from `MartinGallagher-code/envoy` via `git subtree split --prefix=glean` (history
  preserved: 15 glean commits replayed to repo root) and merged onto the existing
  repo (LICENSE retained; the stub README replaced by the tree's real README).
- **Restored the `extract/strategies/build/` directory (16 strategies + HANDOFF).**
  These files were silently dropped when the tree was committed to envoy: envoy's
  root `.gitignore` has a `build/` rule (for Python build artifacts) that matched
  `glean/extract/strategies/build/`, so the 16 build-tool strategies (`cargo-tree`,
  `cobertura`, `compiler-diagnostics`, `coverage`, `github-actions`, `go-mod-graph`,
  `gradle-output`, `junit-xml`, `make-stats`, `maven-output`, `npm-list`, `pip-list`,
  `sanitizer`, `test-results`, `test-summary`, `valgrind`) were never tracked even
  though `VENDOR.json` counted them (205). Their tests/goldens/samples *were*
  tracked, so the suite failed 17/219 until the strategies were restored. Recovered
  from `EnvoyExtract/strategies/build/` at the vendor SHA (`81bcb18`) so they match
  the rest of the vendored tree's goldens. Strategy count is now the recorded 205.
- **Added a root `VERSION` file (`1.2.1`).** The vendored extract engine resolves
  the canonical suite version by walking up for a `VERSION` file (`lib/envoy_version.sh`);
  envoy's lived at the repo root, outside `glean/`, so the subtree split left it
  behind and `--version` reported `0.0.0+unknown`. Restored at the extraction-point
  version so `extract/tests/test_interface.sh` passes.
- Added a `.gitignore` for the standalone repo (runtime `.glean/` store, backups,
  Python cache). Deliberately omits a bare `build/` rule — that pattern is exactly
  what dropped the build strategies upstream.
- Verified green standalone (no sibling Envoy present): extract 219/219 test files,
  smoke 33/33, transform 8/8, analyze engine suite 0 failures, `glean doctor` ok.
- Note for future re-syncs: `tools/sync-extract.sh` pointed at an envoy checkout
  will re-copy `strategies/build/` to disk, but envoy's `build/` gitignore rule
  means a plain `git add` there still won't track them — fix envoy's `.gitignore`
  or use `git add -f`. In this repo the files are tracked normally.
- Files: `VERSION`, `.gitignore`, `extract/strategies/build/*` (17), `README.md`.

## 2026-07-05 — standalone repo scaffolding: CLAUDE.md + CI workflow
- Added `CLAUDE.md` (project instructions for the standalone repo: layout, the
  "don't hand-edit vendored trees, re-sync from upstream" rule, doc + testing
  conventions, mawk-safety + symlink + `GLEAN_*` invariants).
- Added `.github/workflows/ci.yml` — inert in the upstream Envoy repo (GitHub
  only runs root `.github/`), active once glean is its own repo. Jobs: `smoke`
  (tests/smoke.sh), `transform` (transform/tests/test_melt.sh), `extract-suite`
  (extract/tests/run_tests.sh), `analyze-engine` (engine tests on gawk, excluding
  the un-vendored browse/dashboard tests), and `docs` (require the core docs).
  Paths are glean-root-relative. Validated: YAML parses (5 jobs), docs check
  passes, the analyze loop runs (only the known mawk-sensitive `test_correctness`
  fails locally — the CI job installs gawk for exactly that).
- Files: `glean/CLAUDE.md`, `glean/.github/workflows/ci.yml`.

## 2026-07-05 — prep for extraction to a standalone repository (revised Phase 5)
- Decision: rather than hard-cutting the `Envoy*` trees in place, glean is
  extracted into its own repo; Envoy stays intact as upstream. Made the tree
  self-documenting/standalone-ready:
  - Copied the design doc into the tree (`docs/0001-rename-and-simplification.md`)
    and repointed the `README`/`HANDOFF` links to it (they referenced the
    envoy-root `../docs/...`, which dangles at repo root).
  - Documented the standalone model in `README`/`HANDOFF`: vendored
    `extract/`/`analyze/`/`transform/`/`lib/` are canonical; `tools/sync-*.sh`
    require an Envoy checkout via `ENVOY_EXTRACT_SRC`/`ENVOY_ANALYZE_SRC`/
    `ENVOY_CAPTURE_SRC` (they error with that hint otherwise); extraction recipe
    (`git subtree split --prefix=glean`).
- Verified: `glean/` copied out of the envoy tree (no sibling `Envoy*`) runs
  fully — `doctor` resolves both engines, smoke 33/33, melt unit test 8/8; sync
  scripts fail helpfully standalone and work with the env overrides.
- Files: `glean/docs/0001-rename-and-simplification.md`, `glean/README.md`,
  `glean/HANDOFF.md`.

## 2026-07-05 — Phase 4: user-facing surface (README, completion, man, installer)
- Added the glean-native rename-plane deliverables: `README.md` (one-tool story +
  command/env reference), `completions/glean.bash` (verb + dataset/capture/path
  completion), `man/glean.1` (renders clean), and `install.sh` (puts `glean` on
  PATH + drops the completion and man page; supports `--uninstall`; installs in
  place, nothing copied out of tree).
- Fixed a symlink-safety bug surfaced by the installer: glean resolved its
  vendored `extract/`/`analyze/`/`transform/` from `dirname(BASH_SOURCE)`, which
  is the *symlink* path when run via a PATH launcher, so it failed with
  "transform module not found". Now resolves the real script dir once
  (`GLEAN_ROOT`, readlink-aware) and all three resolvers use it. Verified `glean`
  runs correctly via the installed symlink.
- Confirmed glean's own env surface is entirely `GLEAN_*`. Smoke → 33 checks
  (adds an install+symlink-launcher guard); all pass.
- Files: `glean/README.md`, `glean/completions/glean.bash`, `glean/man/glean.1`,
  `glean/install.sh`, `glean/glean`, `glean/tests/smoke.sh`.

## 2026-07-05 — import the melt/transform from source (was hand-copied)
- The extract-output transform — the tidy melt (`_core_melt_tidy`) plus the
  schema-union helpers (`_core_union_header`, `_core_align_rows`) — is now
  **imported from EnvoyCapture's `lib/_core.sh`** and vendored to
  `glean/transform/melt.sh` by new `tools/sync-melt.sh`, instead of the earlier
  hand-copied awk in `glean/glean`. `glean` sources the module and calls the
  canonical `_core_*` functions; the three hand-written duplicates
  (`_melt_tidy`/`_union_header`/`_align_rows`) are removed (`_col_overlap`, which
  is glean-specific, stays). A sibling-EnvoyCapture fallback keeps glean working
  before a sync. Added a transform unit test (`glean/transform/tests/test_melt.sh`,
  8 checks) adapted from EnvoyCapture's tidy-melt integration assertions. Smoke
  still 32/32. Version 0.6 → 0.7-proto.
- Files: `glean/glean`, `glean/transform/melt.sh` (vendored),
  `glean/transform/tests/test_melt.sh`, `glean/tools/sync-melt.sh`.

## 2026-07-05 — re-vendor extract engine: +3 everyday-command strategies
- Re-synced `glean/extract/` from upstream after adding `df`, `ps-aux`, and
  `mount` strategies (catalog 202 → 205). glean now auto-detects these common
  inputs: `df -h` (previously `unsorted` at conf 30 → now `df` at 92), `ps aux`
  (`ps-aux`, 90), and `mount` (90) — each producing a tidy one-row-per-record
  dataset with `#N` provenance. Verified end-to-end via `glean run`.
- Files: `glean/extract/**` (re-vendored), `glean/extract/VENDOR.json`.

## 2026-07-05 — schema reconciliation (union columns vs the .v2 split)
- `_store_append` now reconciles a same-typed capture whose column set differs
  from the existing dataset instead of always splitting to a variant. If the
  column overlap (Jaccard) ≥ `GLEAN_RECONCILE_OVERLAP` (default 60%), the two are
  **unioned**: the dataset's header grows to the union of columns, existing rows
  are blank-filled for new columns, and incoming rows are blank-filled for
  missing ones — so same-typed rows (and their `#N` indices) stay in one table
  that `show`/`stats`/`source` see whole. Below the threshold it still splits to
  a numbered variant (`free.v2`). New awk helpers `_col_overlap`/`_union_header`/
  `_align_rows`. Verified both branches (default unions the trimmed `free`;
  threshold 99 forces the `.v2` split). Smoke → 32 checks; all pass. Version
  0.5 → 0.6-proto.
- Files: `glean/glean`, `glean/tests/smoke.sh`.

## 2026-07-05 — stats: vendor the analyze engine, wire `glean stats`
- Vendored the analyze engine from `EnvoyAnalyze/` into `glean/analyze/` (entry
  point + `lib/` + `profiles/` + tests + samples) via new
  `glean/tools/sync-analyze.sh`; it reuses the already-vendored shared libs at
  `glean/lib/` (same `../lib` mechanism as the extract engine). The big
  `pipeline/` dir and the `browse`/`dashboard` tools are intentionally NOT
  vendored — glean only needs the analyze engine.
- New `glean stats <dataset> [analyze-args...]` runs the vendored engine over a
  dataset's TSV (default = key findings; pass `--all`, a numbered analysis list,
  `--format json`, etc.). `doctor` now reports the analyze engine and warns if
  `gawk` is absent (this box has `mawk`; core analyses still work).
- Also vendored the engine's `completions/`, `schemas/`, and `docs/` (needed by
  its test suite) — a first pass omitted them and regressed
  `test_completions`/`test_json_schema` (they pass upstream). Vendored analyze
  **engine tests: 26/27 pass** (excluding `browse`/`dashboard` tests and the two
  browse-backed tests `test_help_overlay`/`test_mdx`, since those tools aren't
  vendored). The single remaining failure, `test_correctness`, **also fails
  upstream** in this `mawk` environment — an environment issue, not a vendoring
  regression. `glean stats` itself is verified end-to-end via the smoke test
  (29 checks; all pass).
- Files: `glean/analyze/**` (vendored), `glean/tools/sync-analyze.sh`,
  `glean/glean`, `glean/tests/smoke.sh`, `glean/HANDOFF.md`.
- **Remaining:** schema reconciliation (union columns vs the `.v2` variant split).

## 2026-07-05 — Store model Stages B + C: controlled dirs + export/import
Completes the git-core directive.
- **Stage B — controlled directories.** `glean control [<dir>]` marks a directory
  as its own capture instance (`<dir>/.glean` with a `CONTROLLED` marker).
  Store resolution now walks up from CWD: `GLEAN_WORKSPACE` override → nearest
  controlled dir → global store. Captures run inside a controlled dir (or a
  subdir) route to its instance, and each capture commit **snapshots the
  directory's contents as context** (`context/manifest.tsv`: path/size/mtime/sha1,
  excluding `.glean`/`.git`). `glean instances` lists controlled dirs (from a
  registry in the global store); `glean uncontrol` releases one (data kept).
- **Stage C — export / import.** `glean export [<file>]` bundles the whole store
  (all datasets + capture commits + tags) into a portable `git bundle`;
  `glean import <file> [<dest>]` reconstitutes it elsewhere. Verified: after a
  move, the imported store's datasets, capture log, and per-row `#N → source`
  provenance are all browsable.
- Fixed a `set -e` escape: the controlled-dir context snapshot in `_ingest` ran
  as a bare `func || true` (current shell), so an internal failure aborted before
  the guard; now wrapped in a subshell.
- Smoke test → 27 checks (adds control/subdir-routing/context/instances +
  export/import round-trip); all pass. Version 0.4 → 0.5-proto.
- Files: `glean/glean`, `glean/tests/smoke.sh`, `glean/HANDOFF.md`,
  `glean/CHANGELOG.md`.
- **Still deferred:** `stats` (vendor envoy-analyze) and schema reconciliation.

## 2026-07-04 — Store model Stage A: global store + per-row provenance
Implements the fuller "git core" directive (row→source traceability, global
store, multi-user).
- **Global store by default:** captures go to `$GLEAN_HOME` (or `~/.glean`) so you
  can capture from any directory without being in a workspace. `GLEAN_WORKSPACE`
  is an explicit override (wins; used by tests). `doctor` reports which store and
  the next row index.
- **Per-row provenance with a visible `#N` index:** every dataset row gets a
  globally-unique index as its first column (shown by `show`). New
  `glean source <#N>` maps a row back to the exact captured input that produced
  it (prints the capture meta + stored `output.txt`). Provenance recorded in
  `provenance.tsv` (`#` → dataset → capture); a monotonic counter in
  `.next_row_id`.
- **Multi-user safe:** a `mkdir`-based store lock (stale-PID break, configurable
  `GLEAN_LOCK_TIMEOUT`) serialises concurrent writers; `git init` uses
  double-checked locking so parallel first-writers to a shared store don't race.
  Verified: 8 concurrent captures into a fresh shared store → 8 distinct indices,
  0 duplicates, git fsck clean.
- `_ingest` now assigns `#N`, writes provenance, and commits under the lock; both
  `run` and pipe-`inject` go through it. Smoke test → 17 checks (adds `#N`,
  `source`, concurrency); all pass. Version 0.3 → 0.4-proto.
- Files: `glean/glean`, `glean/tests/smoke.sh`, `glean/HANDOFF.md`.
- **Still pending (proposal Stages B/C + analyze):** controlled directories,
  export/import, `stats`, schema reconciliation.

## 2026-07-04 — Phase-3: git core — capture-as-commit + restore
- The workspace is now a **git repo**: every capture is one commit tagged
  `capture-<id>`, replacing the flat-TSV-only store. Added verbs:
  - `glean run [--] <cmd>` — execute a binary, capture combined stdout+stderr,
    auto-detect + file it, and commit the capture (records `captures/<id>/meta.tsv`
    + `output.txt`).
  - `glean log` — list captures (id, timestamp, source, strategy, dataset, command).
  - `glean restore <id|latest>` — check a capture's committed tree back out
    (detached) to bring that run back up; `latest` returns to `main`.
- Refactored the extract→classify→melt→store core into a shared `_ingest` used by
  both `run` and pipe-`inject`; both now commit. `doctor` reports git-backed.
- Chosen model: simplified **linear git history** (one commit per capture) rather
  than EnvoyCapture's per-run + `__dataset`/`__results`/`__scripts` orphan-branch
  machinery (proposal 0001 §7).
- Smoke test extended to 11 checks incl. run→log→restore→restore-latest; all pass.
- Still deferred to Phase-3 cont.: `stats` (vendor envoy-analyze) and schema
  reconciliation (union columns vs `.v2` split).
- Files: `glean/glean`, `glean/tests/smoke.sh`, `glean/HANDOFF.md`.

## 2026-07-04 — Phase-2 fix: relayout to extract/ + lib/, vendor missing deps
- The first Phase-2 vendor (below) under-copied: the cross-suite shared libs
  (`envoy_version.sh`, `envoy_progress.sh`, …) and `EnvoyExtract/tools/` were left
  out, so 13 suite tests regressed (`--version`, `-V`, `--progress`,
  `new_strategy.sh`/`review_strategy.sh`) — all green upstream but failing
  vendored. Also, nesting the engine at `lib/extract/` put its `../lib` at the
  confusing `lib/lib`.
- Fix: moved the vendored engine to `glean/extract/` and the shared libs to
  `glean/lib/` (the engine's `../lib`), mirroring the upstream engine-dir +
  sibling-`lib/` layout so the suite resolves paths unchanged. `sync-extract.sh`
  now also vendors `tools/` and the repo-root `lib/*.sh`. All 4 previously-failing
  files pass in the new location (21/21, 8/8, 13/13, 21/21). `glean` `_find_engine`
  updated to `extract/envoy-extract`. **Full vendored suite now genuinely green:
  216/216 test files passed, 1103 assertions, 0 failed (exit 0)** — correcting an
  earlier premature "green" claim that was based on a partial run (the full run
  had in fact exited 1 with the 13 failures above).
- Files: `glean/extract/**` (relocated + `tools/`), `glean/lib/*.sh` (shared),
  `glean/tools/sync-extract.sh`, `glean/extract/README.md`, `glean/glean`,
  `glean/HANDOFF.md`.

## 2026-07-04 — Phase-2: vendor the extract engine into lib/extract/
- Vendored the full extract engine (entry point + `lib/` + all 202 strategies +
  tests + samples; ~1,145 files) from `EnvoyExtract/` into `glean/lib/extract/`
  so the tree is self-contained and runnable without the sibling project.
- Added `tools/sync-extract.sh` — refreshes the vendored copy from `EnvoyExtract/`
  (source of truth until the Phase-5 hard cut) and writes `lib/extract/VENDOR.json`
  (source git SHA, timestamp, component list, strategy/file counts) so drift is
  visible. Supports `--runtime-only`. Added `lib/extract/README.md` (do-not-edit +
  how-to-sync note).
- `glean` `_find_engine` now resolves the vendored copy first; the
  sibling-`EnvoyExtract/` walk-up is demoted to a transition fallback.
- Confirmed the strategy/engine suite passes in the new location
  (`bash glean/lib/extract/tests/run_tests.sh`) and `glean/tests/smoke.sh` still
  passes against the vendored engine.
- Files: `glean/lib/extract/**` (vendored), `glean/tools/sync-extract.sh`,
  `glean/lib/extract/README.md`, `glean/glean`, `glean/HANDOFF.md`.

## 2026-07-04 — Phase-1 prototype
- New `glean/` tree (proposal 0001): single-binary `glean` implementing the
  product's one path — `cmd | glean` auto-detects format via the real extract
  engine (`--emit-meta`, all 198 strategies), melts to one row per record, and
  files it into a per-type dataset. Verbs: default inject, `ls`, `show`,
  `triage`, `doctor`, `help`.
- Minimal flat-TSV store under `$GLEAN_WORKSPACE` (default `./.glean`); differing
  headers split to numbered variants (git store + schema reconciliation deferred
  to Phase 3). Engine resolved via sibling `EnvoyExtract/` fallback until Phase 2
  copies it under `glean/lib/extract/`.
- Files: `glean/glean`, `glean/HANDOFF.md`, `glean/CHANGELOG.md`,
  `glean/tests/smoke.sh`.
