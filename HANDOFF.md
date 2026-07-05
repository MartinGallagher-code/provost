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

## Phase 3 — git core (done)

The workspace is now a **git repo** (`$GLEAN_WORKSPACE`, default `./.glean`).
Every capture is one commit, tagged `capture-<id>`, so a run can be brought back
up later:

```bash
glean run free -m         # execute a binary, capture its output AS A COMMIT
glean log                 # list captures (the git history): id, when, cmd, dataset
glean restore c0003       # check that capture's committed tree back out (detached)
glean restore latest      # return to the tip (main)
```

`run` and pipe-`inject` share one `_ingest` pipeline (extract → classify → melt →
store → record capture → commit). Each capture writes `captures/<id>/{meta.tsv,
output.txt}` alongside the dataset change, all in one commit. This is the
simplified linear-history model chosen over EnvoyCapture's per-run + triple-orphan
-branch machinery (proposal 0001 §7; decision made when the ask-tool was
interrupted — revisit if full EnvoyCapture fidelity is wanted).

## Store model — Stage A (done)

Fuller realisation of the user's git-core directive (see proposal 0001 §5a):

- **Global store by default** — `$GLEAN_HOME` or `~/.glean`; capture from anywhere.
  `GLEAN_WORKSPACE` explicit override wins (tests use it).
- **Per-row provenance** — every dataset row has a globally-unique visible `#N`
  index (first column); `glean source <#N>` returns the exact captured input that
  produced it (via `provenance.tsv` → `captures/<id>/output.txt`).
- **Multi-user** — `mkdir` store lock + double-checked `git init`; verified under
  8-way concurrency (distinct ids, 0 dups, fsck clean). Point `GLEAN_HOME` at a
  shared group-writable dir to collaborate.

### Stage B (done) — controlled directories
`glean control [<dir>]` makes `<dir>` its own instance (`<dir>/.glean` +
`CONTROLLED` marker). Resolution walks up from CWD (override → controlled →
global). Captures inside route there and snapshot the directory's contents as
commit context (`context/manifest.tsv`). `glean instances` lists them (registry
in the global store); `glean uncontrol` releases (data kept).

### Stage C (done) — export / import
`glean export [<file>]` → a portable `git bundle` of the whole store;
`glean import <file> [<dest>]` reconstitutes it elsewhere. Datasets, capture log,
and per-row `#N → source` provenance all survive the move (verified in smoke).

## Analyze — done

`envoy-analyze` is vendored at `glean/analyze/` (via `tools/sync-analyze.sh`),
reusing the shared libs at `glean/lib/`. `glean stats <dataset> [args]` runs it
over a dataset's TSV. `browse`/`dashboard`/`pipeline` are intentionally NOT
vendored, so their tests are excluded from the vendored analyze suite.

## Schema reconciliation — done

`_store_append` unions a differing-column same-type capture into the base dataset
when column overlap ≥ `GLEAN_RECONCILE_OVERLAP` (default 60%), blank-filling both
sides; below the threshold it splits to a numbered variant (`free.v2`). Keeps
same-typed rows and their `#N` indices in one table.

## Next steps (per proposal phases)

1. **Phase 3 (cont.)** — vendor envoy-analyze under `glean/analyze/` and wire
   `glean stats <dataset>`; add schema reconciliation to `_store_append` (union
   columns instead of splitting to `.v2`). The store-model directive (Stages A–C)
   is now complete.
2. **Phase 4** — rename plane: env vars (`GLEAN_*`, already used here), one man
   page, completions, packaging, README.
3. **Phase 5** — hard-cut the `Envoy*` trees + satellites; archive
   `scenarios/`/`web/`/`tickets/` to a sibling repo. At that point retire
   `tools/sync-extract.sh` — `extract/` becomes canonical.

## Open questions

Tracked in the proposal §10. The two resolved since: deprecated `envoy-*`
wrappers → **hard cut**; `scenarios/`/`web/`/`tickets/` → **archive**.

## Tests

`tests/smoke.sh` exercises inject → ls → show end-to-end against a temp
workspace. Run: `bash glean/tests/smoke.sh`.
