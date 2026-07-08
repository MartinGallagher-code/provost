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
(moved to `text-inputs/`), 149 parse-wrong.

**Done — aligned-columns opt-in positional parsing (~50 tools, the biggest
cluster).** docker/kubectl/helm/crictl/dnf/az/gcloud tables were shredding
multi-word headers (`IMAGE ID`) and values (`2 weeks ago`) on whitespace. Fixed
by `_ac_aligned` (are ≥80% of data rows aligned to the header's 2+-space column
starts?) gating `_ac_assign` (assign each token to its header column region,
rejoining multi-word cells). Only *cleanly-aligned* blocks get positional
parsing; irregular single-space headers (ps/df), right-aligned-overflow numerics
(ps-aux-sort), two-line headers (vmstat/dstat), and headerless tables keep the
known-good tokenization. This opt-in gate is the key: two earlier
*unconditional* positional rewrites each regressed a different set of common
tools (all-row-whitespace broke ps-aux-sort/vmstat; header-region-only broke
ps/df) because multi-word values and right-aligned numerics need opposite
column-detection — the gate sidesteps that by only firing where the header and
data agree. **A second gate was added (2026-07-09):** `_ac_aligned` alone still
mis-fired on single-token tables whose header uses single spaces between real
labels (df `Used Avail Use%`, lsblk, ss, elasticsearch, losetup) — the header's
2-space split under-counts columns and crams them. Positional now *also* requires
a data row to carry more whitespace tokens than the header has labels (a genuine
multi-word cell), so single-token tables stay on tokenization. All corpus goldens
were regenerated afterward (`run.sh --golden`: 980/0). `hg-paths` was reclassified
`table`→`kv` (it is a `key = value` block like `ansible-config-dump`). Also
retired the `kubectl` and `container-top` bespokes (they
transposed to one wide row + mis-split; aligned-columns now covers them as
records). Shadow narrowings landed: `hg-branches`, `git-log`, `version-string`,
`pip-list`, `colon-fields`, `docker-ps`, plus the batch-1 fixes.

**Remaining parse-wrong tail, by cluster — the next work:**
1. **Greedy bespoke/generic shadows still to narrow.** DONE this pass:
   `git-config-list` (→ `equals`, added `.` to the key class; reclassified `kv`),
   `jmap-histo` (→ its bespoke; `sqlite-output` column-mode now needs a *segmented*
   dash separator, not a solid rule), `dnf-history-list` (`sqlite-output` pipe mode
   skips the dash rule and underscores multi-word headers — a general fix for every
   multi-word-header sqlite table). **Still hard / deferred** (genuine multi-line
   records, trees, diffstats — need dedicated structural parsers, not just a decline;
   verified that aligned-columns does NOT cleanly parse them): `gpg-list-secret-keys`
   (multi-line key blocks), `gradle-q-dependencies` (dependency tree), `git-diff-stat`
   / `git-stash-show-stat` (`file | N graph` diffstat), `git-branch`/`-a` (branch
   list — `line-records` c1/c2 is acceptable), `ghc-info` (Haskell tuples), `cgget` /
   `java-showsettings` / `jcmd-heap-info` (nested key blocks), `flatpak-list` /
   `ip-br-addr` / `aptitude-search` / `ipmitool-sdr` / `deno-info` / `bundle-outdated`
   / `ip6tables-l` (pkg-config shadows whose data is misaligned / headerless-pipe /
   ` - `-delimited / multi-section — no clean existing home), `etcdctl-alarm-list` /
   `ipset-list` (proc-stat). git-lfs/for-each-ref/gsutil-du, hg-log/heads/summary,
   dig-short, git-submodule, composer-outdated, helm-list, kubectl-get-*,
   docker/podman top, crictl-ps are already fixed.
2. **Record-vs-one-wide-row** (a multi-record dump transposed into a single wide
   row — needs repeated-key/record detection): `yaml` (dpkg-s, edac-util,
   dotnet-nuget-locals, kubectl-config-view, flatpak-info), `ini` (dbmate-status,
   gcloud-config-list), `labeled-records` (blkid, bridge-link), `equals`
   (conntrack-count), `inline-kv` (conntrack, conntrack-L). DONE:
   `aureport-summary` / `duplicity` → `colons` (`vertical-line` now declines
   `label: value` banner blocks); `dmesg` / `ausearch-avc` → `text-inputs/`
   (free-form logs). `chronyc-sources` still on `vertical-line` (an aligned NTP
   table — would be better on aligned-columns but routing it risks vertical-line's
   own tables; left as-is).
3. **Nested-heading grouping** (a section heading should open a sub-group, not be
   flattened/duplicated): DONE — `ip-addr` / `ip-link` now have the bespoke
   `ip-link` parser (one row per interface). Still hard: `ifconfig` (RX/TX keyword
   collision — `packets`/`bytes` repeat across RX and TX lines, so a generic
   keyword-value parse needs RX_/TX_ prefixing) and `iwconfig` (inline
   `key:value`/`key=value`), `dovecot-n` (nested `{ }` config blocks),
   `key-value` (fail2ban-status `|-` tree, hdparm-i); `git-remote-show-origin`,
   `cpupower-idle-info`, `httpd-V`, `biosdecode`, `btrfs-filesystem-show` already
   parse acceptably.
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
2. **Prune redundant per-tool strategies — investigated 2026-07-09, essentially
   DONE already.** The obviously-redundant columnar bespokes (`df`, `ps-aux`, `ps`,
   `ss`, `lsblk`, `vmstat`, `dstat`, `netstat`, `top`, `systemctl`, `who`, `w`,
   `kubectl`, `container-top`) were already removed in earlier sessions — none of
   them exist now. A rigorous sweep (full-mode winner for all 1040 corpus tools,
   then a byte-for-byte compare of each bespoke's output against the generic
   golden) found **no remaining strategy is safely removable**: every bespoke that
   still shadows a generic-covered tool produces *better or distinct* output, not
   redundant output — e.g. `mount` → named `device/mount_point/fstype/options`
   (generic gives raw `c1..c6` with literal `on`/`type`/`(rw,relatime)`), `free`
   labels the `Mem`/`Swap` row, `ls-l` joins the split date, `kv-pairs` strips the
   `, ` delimiter `inline-kv` leaves. 420 distinct strategies (421 files — a stray
   duplicate `## Name: perf-stat` in `benchmark/` and `profiling/`; resolving that
   needs picking the canonical impl, since both are shadowed by `perf-counters` in
   the corpus). Net: the count (420) stands; do not delete value-adding bespokes to
   shrink it.
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
