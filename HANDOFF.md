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
Runs the **extract engine** (all strategies at `extract/`) via its
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

## Direction: fewer strategies, more generic tidying

The active goal is to tidy **all common tool outputs with a minimum of
strategies** — lean on the ~12 generic parsers (`extract/strategies/delimited/`
+ `structured/`) instead of a bespoke strategy per tool, and delete the
redundant per-tool strategies once the generic parsers cover them.

Measured by `tests/corpus/` (see its README + `COVERAGE.md`): **300 common Linux
tools** (with varied output per tool), a correctness manifest, golden outputs,
and one parallel batch harness `run.sh`. **All 300 tidy: 264 via a generic parser,
36 via a bespoke one** (no remaining gaps). The generic parsers carry the common
264; the 36 bespoke are idiosyncratic format families (sysstat banners
`mpstat`/`sar`/`pidstat`; `ping`/`traceroute`/`w`; `dmidecode`/`lspci`/`uname`/
`uptime`; the monitoring cluster `perf-top`/`turbostat`/`slabtop`/`iotop`/`iftop`/
`nethogs`/`perf-counters`; storage trees `zpool-status`/`btrfs-filesystem-show`/
`multipath-ll`/`lsusb-t`; grouped network stats `netstat-s`/`nft-list-ruleset`/
`ip-maddr`/`rfkill-list`/`bridge-fdb`; `vault-status`/`memcached-stats`/`pmap`/
`numastat`/`zypper-search`; and a handful of binutils / VCS / security tools).
`run.sh --coverage` regenerates `COVERAGE.md` (the queryable ✅/✅ᵇ list). The
extract engine selects the **lowest-priority-number** matching strategy (confidence
is mainly a threshold gate), so making a generic parser win is about its
`## Priority` and `detect()`.

The generic parsers covering the corpus: `aligned-columns` (header, headerless,
two-line; defers pure key/value blocks and collapses `#`-comment headers),
`bracket-log`, `inline-kv`, `yaml`, `key-value`, `equals`, `colons` (gated to ≥40%
`key:` lines), `colon-fields` (colon-delimited records — `/etc/passwd`/`group`/
`getent`), `indented-hierarchy`, `line-records`, `labeled-records`, `tree-view`,
`vertical-line`, `psql-table` (box tables), `version-string`, and `text-lines`
(last-resort one-column dump).

## Pruning redundant strategies (in progress)

Removing bespoke per-tool strategies the generic parsers now cover — the payoff of
the whole effort. Done so far (−5): `ss` (was broken — emitted a wide non-tidy row
and shadowed the good `ss-tulnp`), `df`, `ps-aux`, `lsblk`, `vmstat` (now handled
by generic `aligned-columns`). Method: `tests/corpus/run.sh` prints generic-vs-full
melt dims per tool — prune where generic is tidy-equal-or-better, delete the
strategy + its `test_strategy_*.sh` + `golden/*.txt` + `samples/*` + any snapshot
case, and keep the extract suite green. Broken/shadowing bespokes are the
highest-value targets. Candidates still to review: `env-vars` (vs `equals`),
`iostat`/`netstat`/`top`/`systemctl`/`who` (already generic — check for a bespoke),
and the long tail once the corpus is broader. Keep bespokes that are clearly
better than the generic (`mount`, `free`, `docker-ps`, `ip-route`, `ls-l` give
nicer columns).

## Next steps

1. **Grow the corpus toward broad coverage** (in progress) — more common tools
   and *varied* output per tool (flags/formats): `mpstat`, `sar`, `lsof`, `du`,
   `ip -s link`, `journalctl`, `ps -ef`, `dmidecode`, `ethtool`, `nmcli`,
   `apt list`, `systemctl status`, … For each: add `inputs/<tool>.txt`, a
   `expected.tsv` row, run `run.sh`, close any new gap in the generic parsers,
   then `run.sh --update-golden`. `COVERAGE.md` stays the queryable record.
2. **Then prune** the now-redundant per-tool strategies (`df`, `ps-aux`, `ss`,
   `lsblk`, `mount`, `iostat`, `netstat`, `top`, `systemctl`, …) that the generic
   parsers already cover in full mode — the payoff of the whole effort (fewer
   strategies). Verify full-mode tidy stays intact as each is removed.
3. Optional: drop the stray `total_entries` column the columnar melt emits (minor
   tidy noise; touches `aligned-columns`/`bracket-log` goldens).
4. Optional: rename the internal `envoy-*` binaries / `envoy_*.sh` libs to
   `glean`-native names (large, internals-only).

## Tests

```bash
bash tests/smoke.sh                 # end-to-end (33 checks)          [CI]
bash transform/tests/test_melt.sh   # transform unit (8 checks)       [CI]
bash extract/tests/run_tests.sh     # extract strategy + engine suite [CI: 214/214]
```

The analyze engine suite is also CI-enforced, but the raw
`analyze/tests/run_tests.sh` is red out of the box: it includes tests for the
`browse`/`dashboard` surfaces glean intentionally omits. CI runs a filtered
subset (skipping `test_browse_*`/`test_dashboard_*`/`test_help_overlay.sh`/
`test_mdx.sh`, with `gawk` installed) — see the `analyze-engine` job in
`.github/workflows/ci.yml`.
