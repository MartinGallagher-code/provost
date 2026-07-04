# Handoff — glean/ (Phase-2)

## Status: Phase-2 — extract engine vendored & self-contained

`glean` is the new single-binary tool proposed in
[docs/proposals/0001-glean-rename-and-simplification.md](../docs/proposals/0001-glean-rename-and-simplification.md)
to replace the three-binary `envoy-*` suite. This directory is the *fresh tree*
the proposal calls for — built from the one product path, not migrated in place.

## What works now

The default verb plus `ls` / `show` / `triage` / `doctor` / `help`:

```bash
free -m        | ./glean/glean           # auto-detect → tidy dataset, filed by type
docker stats   | ./glean/glean
./glean/glean ls                          # list datasets
./glean/glean show free                   # present a dataset as a tidy table
./glean/glean triage                      # low-confidence / unmatched bucket
./glean/glean doctor                      # engine reachability check
```

The default verb runs the **real extract engine** (all 198 strategies) via its
`--emit-meta -f tsv --max-strategies 1` contract, classifies by the winning
strategy + confidence, melts the wide `entry<N>.<field>` output to **one row per
record** (port of EnvoyCapture `_core_melt_tidy`), and appends it to a per-type
dataset.

## Phase 2 — engine vendored (done)

The extract engine + all strategies now live **inside** the tree, vendored from
`EnvoyExtract/` by `tools/sync-extract.sh`:

- `extract/` — engine entry point + `lib/` + 202 strategies + `tools/` + tests +
  samples.
- `lib/` — the cross-suite shared libs (`envoy_*.sh`) the engine sources via its
  `../lib`, vendored from the repo-root `lib/`. This layout mirrors how the
  engine resolves paths upstream (engine dir with a sibling `lib/`), so its suite
  runs unchanged.

`glean` resolves the vendored engine (`extract/envoy-extract`) first; the
sibling-`EnvoyExtract/` walk-up remains only as a transition fallback.

- **Updatable from upstream:** `bash glean/tools/sync-extract.sh` re-vendors the
  engine + shared libs from `EnvoyExtract/` and repo-root `lib/` (source of truth
  until the Phase-5 hard cut) and rewrites `extract/VENDOR.json` (source git SHA,
  timestamp, counts). Do not hand-edit vendored files — edit upstream and
  re-sync. See `extract/README.md`.
- **Suite runs in-place:** `bash glean/extract/tests/run_tests.sh` →
  **216/216 test files passed, 1103 assertions, 0 failed** (86 golden cases
  skipped), exit 0. `glean/tests/smoke.sh` also passes against the vendored engine.

> **Layout note:** an earlier take vendored to `lib/extract/`, which put the
> engine's `../lib` at the confusing `lib/lib` and left the shared libs +
> `tools/` un-vendored (13 suite failures: `--version`, `--progress`,
> `new_strategy.sh`/`review_strategy.sh`). Fixed by moving the engine to
> `extract/` with shared libs at `lib/` and vendoring `tools/` + the shared libs.

## Deliberately minimal (not bugs)

- **Store** is flat TSV files under `$GLEAN_WORKSPACE` (default `./.glean`). No
  git branches, no schema *reconciliation* — a differing header splits to a
  numbered variant (`free.v2`), rather than union-merging columns. The git store
  + reconciliation is Phase 3 (it lives in EnvoyCapture `lib/_core.sh` /
  `cmd_inject.sh` today and will be ported/trimmed).
- **No `stats`** yet — that's the carried-over analyze core, Phase 3.

## Next steps (per proposal phases)

1. **Phase 3** — implement `stats` (port analyze core) and replace the minimal
   flat store with the trimmed git-based store + schema reconciliation.
2. **Phase 4** — rename plane: env vars (`GLEAN_*`, already used here), one man
   page, completions, packaging, README.
3. **Phase 5** — hard-cut the `Envoy*` trees + satellites; archive
   `scenarios/`/`web/`/`tickets/` to a sibling repo. At that point retire
   `tools/sync-extract.sh` — `lib/extract/` becomes canonical.

## Open questions

Tracked in the proposal §10. The two resolved since: deprecated `envoy-*`
wrappers → **hard cut**; `scenarios/`/`web/`/`tickets/` → **archive**.

## Tests

`tests/smoke.sh` exercises inject → ls → show end-to-end against a temp
workspace. Run: `bash glean/tests/smoke.sh`.
