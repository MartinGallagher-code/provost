# Handoff — glean

## Status: Extracted — glean is now its own repository (Phases 2–4 done, standalone)

> **2026-07-05 — extraction complete.** This repo was split out of
> `MartinGallagher-code/envoy` via `git subtree split --prefix=glean` (glean
> history preserved). Two things that lived outside `glean/` in envoy and had to
> be restored here: the root **`VERSION`** file (the vendored engine walks up for
> it; absent → `--version` read `0.0.0+unknown`) and **`extract/strategies/build/`**
> (16 strategies that envoy's `build/` gitignore rule had silently kept untracked,
> so they never made it into the subtree — restored from `EnvoyExtract` at the
> vendor SHA `81bcb18`). Full suite green standalone: extract 219/219, smoke 33/33,
> transform 8/8, analyze 0 failures. Re-syncing from envoy will re-hit that
> `build/` gitignore rule — see CHANGELOG note.

`glean` is the new single-binary tool proposed in
[docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md)
to replace the three-binary `envoy-*` suite. This directory is the *fresh tree*
the proposal calls for — built from the one product path, not migrated in place.

### Standalone-repo model (Phase 5, revised)

Instead of hard-cutting the `Envoy*` trees in place, `glean/` is extracted into
its **own repository**; the Envoy repo stays intact as the upstream source. This
tree is already self-contained — `glean` resolves its vendored
`extract/`/`analyze/`/`transform/` from its own directory (`GLEAN_ROOT`), so it
runs with no sibling `Envoy*` present (verified: copied out of tree, smoke 33/33).

- The vendored `extract/`, `analyze/`, `transform/`, and `lib/` trees are
  **canonical** in the standalone repo.
- `tools/sync-*.sh` still work for pulling upstream changes, but require an Envoy
  checkout — point them at it with `ENVOY_EXTRACT_SRC` / `ENVOY_ANALYZE_SRC` /
  `ENVOY_CAPTURE_SRC` (they error with that hint when no sibling is found).
- Extract preserving history with, e.g.,
  `git subtree split --prefix=glean -b glean-export` → push that branch to the
  new repo.

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
store → record capture → commit). The melt/transform step (`_core_melt_tidy` +
the schema-union helpers) is **imported** from EnvoyCapture via
`tools/sync-melt.sh` into `glean/transform/melt.sh` (not re-implemented); unit
test at `glean/transform/tests/test_melt.sh`. Each capture writes `captures/<id>/{meta.tsv,
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

**Phases 2, 3, 4 are done.** Extract + analyze + transform vendored; git core,
provenance, controlled dirs, export/import, stats, and reconciliation all built;
Phase-4 surface (README, `completions/glean.bash`, `man/glean.1`, `install.sh`)
shipped and glean is symlink-safe on PATH.

1. **Phase 5 (remaining)** — hard-cut the `Envoy*` trees + satellites; archive
   `scenarios/`/`web/`/`tickets/` to a sibling repo. At that point retire the
   `tools/sync-*.sh` scripts — `glean/{extract,analyze,transform}/` become
   canonical. This is the consequential step (deletes the source-of-truth trees),
   so it should be its own reviewed change.
2. Ongoing: more extract strategies (`du`, `sensors`, `mpstat`, `ps -ef`, …).

## Open questions

Tracked in the proposal §10. The two resolved since: deprecated `envoy-*`
wrappers → **hard cut**; `scenarios/`/`web/`/`tickets/` → **archive**.

## Tests

`tests/smoke.sh` exercises inject → ls → show end-to-end against a temp
workspace. Run: `bash glean/tests/smoke.sh`.
