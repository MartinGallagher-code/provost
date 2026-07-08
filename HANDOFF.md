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

Measured by `tests/corpus/` (see its README + `COVERAGE.md`): **1050 common Linux
tools** (with varied output per tool), a correctness manifest, golden outputs,
and one parallel batch harness `run.sh`. **All 1050 tidy: the bulk via generic parsers,
plus format-family parsers for idiosyncratic tools** (no remaining gaps). The generic parsers carry the bulk;
the tail are idiosyncratic format families (sysstat banners
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

## Output-quality vetting (2026-07-08)

Two correctness passes over what tools actually emit (not just row/column shape):

- **Values keep their spaces.** ~200 strategies were underscoring spaces in
  emitted VALUES (`${v// /_}`), mangling multi-word data. Removed from every
  value path (kept it on field NAMES/headers, kept tab→`_` for TSV safety);
  regenerated 414 goldens and 53 test assertions. `glean` now shows
  e.g. R nickname "Eye Holes", cert issuer "C=US, O=DigiCert Inc",
  systemd descriptions and commit subjects verbatim.
- **Box-table shadowing.** `pipe-table`/`sqlite-output`/`strace-summary`/
  `fixed-width` now decline `+---+` box tables so `psql-table`'s box parser wins
  them — fixed ~55 `aws --output table`/mysql/pg/pgbouncer grids that were
  flattened to one/few columns (aws-ec2-describe-instances 2→8 cols). Done via
  `detect()` narrowing (no priority changes), so bespoke parsers and non-box
  tools are untouched.

### 500-input review (2026-07-09)

Classified ~500 inputs (ok / just-text / parse-wrong). 339 ok, 11 just-text
(moved to `text-inputs/`), 149 parse-wrong. Fixed:
- `colon-fields` identifier-list decline (ARNs), `docker-ps` COMMAND guard
  (docker-stats/buildah), plus the batch-1 fixes.

**Deferred — aligned-columns multi-word mis-split (~52 tools, the biggest
cluster).** docker/kubectl/helm/crictl/dnf/az/ip tables shred multi-word headers
(`IMAGE ID`) and values (`2 weeks ago`) because aligned-columns tokenizes on
whitespace. Two positional rewrites were attempted and both regressed a
*different* set of common tools, so both were reverted:
- All-row whitespace-column boundaries: broke right-aligned numeric columns
  (`ps-aux-sort` merged VSZ/RSS — the inter-column gap moves) and two-line headers
  (`vmstat`/`dstat` — the group row breaks the boundaries).
- Header-region token assignment (split header on 2+ spaces, assign each data
  token to the region its start falls in): fixed docker/kubectl but broke `ps`/`df`
  whose headers are *irregularly* spaced (short labels, mixed single/2+ gaps).
The two data shapes need opposite strategies: a multi-word value needs the header
to define column regions so internal spaces aren't split; a right-aligned numeric
column needs data-gap detection because the header is irregular. A robust fix
needs proper fixed-width column inference (cluster token start/end positions
across data rows, à la `pandas.read_fwf`), which is a dedicated effort — not a
detect/tokenize tweak. Until then these ~52 stay mis-split (the pre-existing
baseline). The safe ` = ` assignment-block decline guard on aligned-columns is
kept.

**Remaining parse-wrong tail (~85 tools), by cluster — the next work:**
1. **Greedy bespoke/generic shadows** (narrow `detect()`; the freed tools are now
   handled well by positional aligned-columns): `kubectl` (helm-list/-all,
   docker-compose-ps, kubectl-get-all/daemonset), `sqlite-output` (jmap-histo,
   git-stash-show-stat, gpg-list-secret-keys, gradle-q-dependencies,
   dnf-history-list, git-diff-stat), `pkg-config` (aptitude-search,
   bundle-outdated, flatpak-list, ip-br-addr, ip6tables-l, ipmitool-sdr, deno-info),
   `git-log` (git-for-each-ref, git-lfs-ls-files, gsutil-du), `hg-branches`
   (hg-heads/-log/-summary), `proc-stat` (etcdctl-alarm-list, ipset-list),
   `container-top`, `version-string`, `pip-list`, `env-vars`, `line-records`
   (git-branch/-a, git-config-list, ghc-info, cgget, java-showsettings, jcmd-heap-info).
2. **Record-vs-one-wide-row** (a multi-record dump transposed into a single wide
   row — needs repeated-key/record detection): `yaml` (dpkg-s, edac-util,
   dotnet-nuget-locals, kubectl-config-view, flatpak-info), `ini` (dbmate-status,
   dmesg, gcloud-config-list), `labeled-records` (blkid, bridge-link),
   `vertical-line` (aureport-summary, chronyc-sources, duplicity), `equals`
   (ausearch-avc, conntrack-count), `inline-kv` (conntrack, conntrack-L).
3. **Nested-heading grouping** (a section heading should open a sub-group, not be
   flattened/duplicated): `indented-hierarchy` (ip-addr, ip-link, ifconfig,
   dovecot-n, iwconfig), `key-value` (fail2ban-status, git-remote-show-origin,
   cpupower-idle-info, hdparm-i, httpd-V), `biosdecode`, `btrfs-filesystem-show`.
4. **Colon inside a value** (MAC/IPv6 split): `colons` (iw-station-dump, ethtool-a),
   `ifconfig`.
5. **Genuinely hard / low-ROI**: multi-panel dashboards (`glances`, `atop`),
   wide variable-width date columns (`helm-history`, `docker-history`), deeply
   nested JSON (`cargo-metadata`).

Method to close each: `env -u GIT_DIR bash extract/envoy-extract --emit-meta -f
tsv --max-strategies 1 <input>` shows the winner; narrow the greedy parser's
`detect()` (or improve the record/heading modeling), then verify no regression
with the extract suite + a full-corpus winner scan. The corpus goldens under
`tests/corpus/expected/` are generic-mode, regenerated with
`run.sh --update-golden`; `run.sh --golden` is the (non-CI) regression check.

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
bash tests/smoke.sh                 # end-to-end (49 checks)          [CI]
bash transform/tests/test_melt.sh   # transform unit (8 checks)       [CI]
bash extract/tests/run_tests.sh     # extract strategy + engine suite [CI: 214/214]
```

`smoke.sh` is hermetic — it clears the caller's `GLEAN_*` env (notably
`GLEAN_HOME`) so a stale `~/.glean/extract` engine can't shadow the bundled one
and skew classification. If a real `glean` run misclassifies, check
`glean doctor`: it now warns when the extract engine came from a `GLEAN_HOME`
override rather than the bundled tree.

The analyze engine suite is also CI-enforced, but the raw
`analyze/tests/run_tests.sh` is red out of the box: it includes tests for the
`browse`/`dashboard` surfaces glean intentionally omits. CI runs a filtered
subset (skipping `test_browse_*`/`test_dashboard_*`/`test_help_overlay.sh`/
`test_mdx.sh`, with `gawk` installed) — see the `analyze-engine` job in
`.github/workflows/ci.yml`.
