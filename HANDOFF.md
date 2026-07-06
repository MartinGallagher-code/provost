# Handoff — glean

## Status: Standalone — glean is its own repository, no live tie to Envoy

`glean` is the single-binary tool proposed in
[docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md)
to replace the three-binary `envoy-*` suite. It lives in its own repository and
is **fully self-contained**: the entry point resolves its engines from its own
directory (`GLEAN_ROOT`), so it runs with no external dependencies.

> **2026-07-06 — cut from Envoy.** The `extract/`, `analyze/`, `transform/`, and
> `lib/` trees were originally imported from the Envoy suite, but they are now
> **first-party glean code, maintained in this repo directly.** The old
> `tools/sync-*.sh` re-vendoring scripts and the `VENDOR.json` provenance files
> have been removed, and the sibling-Envoy runtime fallbacks are gone from
> `glean`. Edit these trees in place; add extract strategies here without regard
> to upstream Envoy. Any future re-integration is a deliberate manual merge, not
> a routine sync. (Original import point is recorded in `CHANGELOG.md`.)

## What works now

The default verb plus `ls` / `show` / `stats` / `triage` / `doctor` / `help`, and
the git-core verbs `run` / `log` / `restore` / `source` / `export` / `import` /
`control`:

```bash
free -m        | ./glean            # auto-detect → tidy dataset, filed by type
docker stats   | ./glean
./glean run df -h                   # capture a command's output AS A COMMIT
./glean ls                          # list datasets
./glean show free                   # present a dataset as a tidy table
./glean stats free                  # statistics via the analyze engine
./glean source 5                    # the original input behind row #5
./glean triage                      # low-confidence / unmatched bucket
./glean doctor                      # engine + store check
```

## Architecture

### Extract (the default verb)
Runs the **extract engine** (all 205 strategies at `extract/`) via its
`--emit-meta -f tsv --max-strategies 1` contract, classifies by the winning
strategy + confidence, melts the wide `entry<N>.<field>` output to **one row per
record**, and appends it to a per-type dataset. The engine sources the shared
libs at `lib/` (its `../lib`). To add a format, drop a strategy under
`extract/strategies/` with its sample + golden fixtures and run
`bash extract/tests/run_tests.sh`.

### Transform (`transform/melt.sh`)
The tidy melt (`_core_melt_tidy`) and schema-union helpers (`_core_union_header`,
`_core_align_rows`) live here, first-party. `run` and pipe-`inject` share one
`_ingest` pipeline (extract → classify → melt → store → record capture → commit).
Unit test: `bash transform/tests/test_melt.sh`.

### Git core
The store is a **git repo** (`$GLEAN_WORKSPACE`). Every capture is one commit,
tagged `capture-<id>`; each writes `captures/<id>/{meta.tsv,output.txt}` alongside
the dataset change. `glean log` lists captures; `glean restore <id|latest>` brings
one back up. This is a simplified linear-history model (proposal 0001 §7), chosen
over EnvoyCapture's per-run + triple-orphan-branch machinery.

### Store model
- **Global by default** — `$GLEAN_HOME` or `~/.glean`; capture from anywhere.
  `GLEAN_WORKSPACE` explicit override wins (tests use it).
- **Per-row provenance** — every dataset row has a globally-unique visible `#N`
  index; `glean source <#N>` returns the exact captured input that produced it
  (via `provenance.tsv` → `captures/<id>/output.txt`).
- **Multi-user** — `mkdir` store lock + double-checked `git init`; verified under
  8-way concurrency (distinct ids, 0 dups, fsck clean).
- **Controlled dirs** — `glean control [<dir>]` makes `<dir>` its own instance
  (`<dir>/.glean` + `CONTROLLED` marker); resolution walks up from CWD
  (override → controlled → global). `glean instances` / `uncontrol` manage them.
- **Export / import** — `glean export [<file>]` writes a portable `git bundle`;
  `glean import <file> [<dest>]` reconstitutes it elsewhere. Datasets, capture
  log, and per-row `#N → source` provenance all survive the move.

### Analyze (`analyze/`)
`glean stats <dataset> [args]` runs the analyze engine over a dataset's TSV,
reusing the shared libs at `lib/`. The `browse`/`dashboard`/`pipeline` surfaces
are intentionally absent; the analyze suite here excludes their tests.

### Schema reconciliation
`_store_append` unions a differing-column same-type capture into the base dataset
when column overlap ≥ `GLEAN_RECONCILE_OVERLAP` (default 60%), blank-filling both
sides; below the threshold it splits to a numbered variant (`free.v2`).

## Next steps

1. **More extract strategies** — now the primary ongoing work, done directly in
   this repo. Candidates: `du`, `sensors`, `mpstat`, `ps -ef`, … Add each under
   `extract/strategies/` with fixtures and keep `extract/tests/run_tests.sh` green.
2. Optional: rename the internal `envoy-*` binaries / `envoy_*.sh` libs to
   `glean`-native names (a large, self-contained change — internals only).

## Tests

```bash
bash tests/smoke.sh                 # end-to-end (33 checks)          [CI]
bash transform/tests/test_melt.sh   # transform unit (8 checks)       [CI]
bash extract/tests/run_tests.sh     # extract strategy + engine suite [CI: 219/219]
```

The analyze engine suite is also CI-enforced, but the raw
`analyze/tests/run_tests.sh` is red out of the box: it includes tests for the
`browse`/`dashboard` surfaces glean intentionally omits. CI runs a filtered
subset (skipping `test_browse_*`/`test_dashboard_*`/`test_help_overlay.sh`/
`test_mdx.sh`, with `gawk` installed) — see the `analyze-engine` job in
`.github/workflows/ci.yml`.
