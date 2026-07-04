# glean — Changelog

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
  updated to `extract/envoy-extract`.
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
