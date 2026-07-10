# Handoff — glean

## Status: Standalone; generic-first refactor + quality audit landed; corpus grown to 2040 inputs (2026-07-10)

> Merged with main's parallel 2026-07-09 work (PR #23): spreadsheet-style
> nameless columns (`A,B,C…` replaces `c1,c2,c3` — see `_col_letter` in
> `extract/lib/_helpers.sh` and docs/0002), 13 never-winning bespokes pruned,
> and 3 mis-shadow priority fixes (`systemctl-status`, `fail2ban-status`,
> `ulimit` — kept as quality keepers here). Corpus goldens regenerated under
> the merged engine.

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
   (29 files, incl. the promoted `bracket-log`). The old `## Technique: yes` header tag had drifted onto ~145
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
   same tool. 35 rows currently cover 37 corpus inputs.
3. **Net 205 bespoke strategies deleted** (375 → 170 strategy files), with
   their samples, goldens, and per-strategy tests. Deletion criterion: every
   corpus input the strategy won stays manifest-tidy via a generic parser or
   hint row — then a golden-quality audit (2026-07-10) diffed all changed
   goldens and restored 15 bespokes whose generic parse was shape-tidy but
   qualitatively worse (`free`, `docker-ps`, `R-version`, `lvdisplay-m`,
   `snmp-output`, …). The 141 survivors are each the proven full-mode winner
   of at least one corpus input.
4. **Coverage is three-tier and honest** (`tests/corpus/COVERAGE.md`):
   ✅ 838 generic auto-detected · ✅ʰ 37 hint-routed · ✅ᵇ 165 bespoke ·
   ⏳ 0. Total **1040/1040**. Goldens are generic-mode output; inputs covered
   only bespokely have no golden. A **held-out generalization set**
   (`tests/corpus/holdout/`, 24 unseen variants, no goldens) scores the
   system the way unseen captures are judged: currently 24/24 tidy —
   12 generic, 10 hint, 2 bespoke.
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

0. **The bespoke tail is measured (2026-07-10 exhaustive sweep).** Every
   ✅ᵇ input was forced through every generic strategy via the hint path
   (detect bypassed) with dispatch-winner verification and content-quality
   review. Result: only 4 quality conversions existed (shipped), and the
   sweep method itself is reusable (`scratchpad sweep.sh` pattern: forced
   MFE_HINTS_FILE row, verify winner == hint name, compare columns AND
   eyeball content). Further reduction requires NEW generic capabilities,
   in observed-demand order: version-banner → named fields (ansible/elixir/
   swift/R banners), nested/stateful multi-line records (lsusb -v, gpg,
   multipath trees), number+unit merge (iotop/iftop), inline-label variants.
   Shape-passing alone is NOT acceptance — 56 of 60 shape-passes were mush.
1. **Whittle the ✅ᵇ tail (164 inputs, 140 strategies).** The labeled-record
   cluster now has two generic parsers (`psql-expanded`, `dashed-sections` —
   2026-07-10); remaining shapes: transpose+key-slug, number+unit merge,
   nested descriptor blocks (lsusb-v) — see `docs/columnar-specs-engine.md`
   for the data-driven columnar precedent. New engine features beat new
   bespokes.
2. **Grow the holdout set** (`tests/corpus/holdout/`, 40 entries, 40/40)
   toward one unseen variant per covered tool, and add locale/width edge
   cases. Treat every holdout failure as a root-cause parser/detect bug, not
   an expectation to relax — the 2026-07-10 round fixed four that way
   (pkg-config header smells, lastb vs lastlog, aligned-columns footer
   legends).
3. Optional: rename the internal `envoy-*` binaries / `envoy_*.sh` libs to
   `glean`-native names (large, internals-only).

Done since the refactor landed: golden-quality audit (restored 13 more
bespokes, promoted bracket-log to generic), traceroute6 timeout hops
(coverage 1040/1040), holdout set 24 → 46 (46/46), generic parsers
psql-expanded + dashed-sections (replaced 2 bespokes, upgraded
pvdisplay/vgdisplay), and dns-records (replaced the 6-strategy DNS family:
dig-answer/dig-output/dig-mx/dig-txt/drill/host_a; upgraded delv +
dig_noall_answer goldens), and the exposition-format + syslog promotions
to the generic tier (label splitting added; syslog gained a majority-of-
lines gate so it can't hijack status blocks). Coverage now
✅ 852 / ✅ʰ 39 / ✅ᵇ 149; holdout 48/48. Then three more rounds
(2026-07-10): json-array (replaced cloud-json-list; upgraded the four
docker/podman inspect goldens), diffstat (took git-diff-stat +
git-stash-show-stat from sqlite-output's broken accidental parse),
snmp-output promoted to structured/, sqlite-output deleted (zero wins
left), and holdout 48 → 66 with the aws-s3-ls/dmsetup-table hint rows
retargeted to line-records (aligned-columns returns empty on ragged
mixed-width rows — found by the holdout). Coverage at that point (pre-corpus-
expansion, 1540 inputs) ✅ 860 / ✅ʰ 39 / ✅ᵇ 141; holdout 66/66. The two +500
expansions then took the corpus to 2040 (see "Corpus size + gaps" below).


## Corpus size + gaps (2139 inputs, 31 ⏳ as of 2026-07-10)

The corpus grew in two +500 expansions of unique never-before-seen tools
(0 basename overlap each): **1040 → 1540 → 2040**, then a **+99 benchmark-tool
set** (2040 → 2139) covering every benchmarking domain (sysbench/fio/iperf/
pgbench/JMH/glmark2/… — 94/99 tidy). Each batch generalized at ~92% with **no
new per-tool code** (batch 1: 466/500; batch 2: 461/500; benchmarks: 94/99).
Two gap-closing rounds added format-level capability only: (1) melt long-form
for lone kv pairs, a `go-struct` parser, text-lines gate fixes, and a rebuilt
aligned-columns header-promotion heuristic (value-token contrast, styled
all-text headers, 2-column value tables, chrome dropping), which fixed 41 of the
earlier 67 ⏳; (2) a `delimited/pipe-table` parser for GitHub-flavored markdown
tables (`| a | b |` + `|---|` rule — BenchmarkDotNet and any markdown table).
Coverage is now **2108 / 2139** (✅ 1915 / ✅ʰ 58 / ✅ᵇ 135); golden regression
1972 pass / 0 fail / 0 deleted; holdout 68/68.

The 31 ⏳ left include 5 benchmark formats (stream-benchmark, kdiskmark-run,
pytest-benchmark, lzbench-run, blender-benchmark) — all the same
multi-word-header + banner shape as the rest of the tail:
- **multi-line / banner-entangled headers** (numastat-p, quota-report,
  vnstat-hourly, frr-show-bgp-summary, sar-cpu, gluster-volume-status,
  watch-diff, stream-benchmark, kdiskmark-run, pytest-benchmark) — the header
  spans 2 ragged lines or shares its token count with a banner, so no
  width/value heuristic can split them safely.
- **ragged first+last multi-word columns** (lzbench-run `zstd 1.5.5 -1` +
  `silesia.tar`, blender-benchmark `NVIDIA GeForce RTX 4090`).
- Earlier tail (ansible-galaxy-list apachectl-S batch-jobs
bluetoothctl-devices ceph-osd-tree clickhouse-parts cryptsetup-status
file-brief frr-show-bgp-summary gcloud-logging-logs-list getent-group
gluster-volume-status hugo-build-stats hurl-report jless-navigate
kafka-topics-describe numastat-p promtool-check-rules pueue-status
pytest-cov-report quota-report sar-cpu scylla-nodetool-status
v4l2-ctl-list-devices vnstat-hourly watch-diff) are the genuinely hard tail:
- **multi-line / banner-entangled headers** (numastat-p, quota-report,
  vnstat-hourly, frr-show-bgp-summary, sar-cpu, gluster-volume-status,
  watch-diff) — the header spans 2 ragged lines or shares its token count
  with a banner, so no width/value heuristic can split them safely.
- **nested / grouped records** (ceph-osd-tree, kafka-topics-describe,
  v4l2-ctl-list-devices, pueue-status, cryptsetup-status, apachectl-S,
  bluetoothctl-devices) — need a "parent row + indented children" reshape.
- **colon-delimited records** (getent-group) and **key: free-text rows**
  (file-brief, hurl-report) — a `first-token = key, rest = value` mode.
- **summary-row / footer entanglement** (pytest-cov-report TOTAL row,
  hurl-report trailer, hugo-build-stats) and **strategy-competition losses**
  (clickhouse-parts to nft-list-tables, promtool/ansible-galaxy to
  line-records keeping a chrome row).
- **genuinely not a dataset** (batch-jobs prose sentence, jless-navigate JSON
  fragment, gcloud single-column NAME header).
- **2-col tables, free-text last column** (aligned-columns can't split a
  header's single-spaced labels from a multi-word value): spin-templates-list,
  vagrant-status, bluetoothctl-devices, ansible-galaxy-list, go-test-summary.
  Needs a "first-token = key, rest = value" generic mode.
- **sysstat timestamp + %% headers**: sar-cpu (header row is data values).
- **nested tab records**: kafka-topics-describe.
- **genuinely non-tabular** (correct ⏳, not datasets): weather-wttr (ASCII
  art), dart-version / iconv-list-count / batch-jobs / glab-ci-status
  (one-liners), helm-version-full (Go `BuildInfo{}` struct), nginx-T-servers
  (config), cosign-verify / tofu-plan-summary / jless-navigate (prose),
  xrandr-query, apachectl-S, apk-policy, cryptsetup-status, promtool-check-rules,
  radvd-status, tokei-output, v4l2-ctl-list-devices, vboxmanage-list-vms,
  frr-show-bgp-summary, gcloud-logging-logs-list.

## Tests

```bash
bash tests/smoke.sh                 # end-to-end (49 checks)          [CI]
bash transform/tests/test_melt.sh   # transform unit (8 checks)       [CI]
bash extract/tests/run_tests.sh     # extract strategy + engine suite [CI: 63/63 files]
ENVOY_ANALYZE_SUPPRESS_AWK_WARNING=1 bash analyze/tests/run_tests.sh  # [CI, green raw]
bash tests/corpus/run.sh --golden   # corpus regression (1972 goldens, non-CI)
bash tests/corpus/run.sh --coverage # regenerates COVERAGE.md
bash tests/corpus/holdout/run.sh    # generalization check on unseen output
```

`smoke.sh` is hermetic — it clears the caller's `GLEAN_*` env (notably
`GLEAN_HOME`) so a stale `~/.glean/extract` engine can't shadow the bundled one
and skew classification. If a real `glean` run misclassifies, check
`glean doctor`: it warns when the extract engine came from a `GLEAN_HOME`
override rather than the bundled tree.
