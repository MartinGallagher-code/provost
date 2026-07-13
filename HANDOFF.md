# Handoff — glean

## Status: Standalone; generic-first refactor + quality audit landed; corpus grown to 3706 inputs; wrapped-cells + tab-collapse fix (2026-07-12) — **3558 tidy, 150 ⏳**

> **2026-07-12 — wrapped cells + tab-collapse bug.** aligned-columns' positional
> path now rejoins continuation lines (only-last-cell grid row = previous row's
> last column wrapped; appended space-joined) — closing kubectl-events/
> systemctl/crontab/desc wrapped fixtures. Chasing why the join didn't fire
> exposed a long-standing bug: `IFS=$'\t' read -ra` collapses EMPTY tab cells,
> shifting all values left — docker-ps rows with empty PORTS had NAME in the
> PORTS column. Tab-safe `_ac_cells` fixes column labeling in 22 covered
> goldens (all audited + re-frozen). tbl-df-wrapped-device stays ⏳ (never
> reaches the positional path). **Now 3558 tidy, 150 ⏳** (✅ 3339 / ✅ʰ 73 /
> ✅ᵇ 144).

> **2026-07-12 — semicolon-values quote-awareness.** The csv treatment:
> `_strat_ssv_split` (quotes structural at field start, `""` escape) drives
> top-level `;` counting and splitting; new low-density band (2-3 separators,
> EVERY line identical count, >=2 lines) alongside the untouched fio dense band.
> Closed 5 ⏳ (European `;`-CSV: embedded `; ` in quoted cells, decimal commas,
> NBSP thousands), improved 4 covered fixtures (blob/token-soup -> real columns).
> Blast scan: 12 fires = fio x2 unchanged + 5 + 4 + 1 non-flip. **Now 3554 tidy,
> 154 ⏳** (✅ 3335 / ✅ʰ 73 / ✅ᵇ 144).

> **2026-07-12 — unicode spaces + CJK headers.** Engine now normalizes exotic
> Unicode horizontal spaces (NBSP, narrow-NBSP, U+2000–U+200A, U+205F,
> ideographic U+3000) to ASCII space — gated once-per-input like the ANSI strip;
> a single normalized NBSP inside "1 234,56" survives the 2+-space column rule so
> grouping and padding coexist. And aligned-columns' labelly check now accepts
> non-ASCII header tokens, so CJK/hangul tables (名前 年齢 都市) get real column
> names instead of the header landing in the data — contained to rows where
> EVERY token is fully non-ASCII (first cut promoted glyph-decorated log lines:
> ⚡️/✖/›/·/🐷 — all 6 victims restored). Closed 7 ⏳; 11 NBSP-family goldens
> re-frozen clean. sed gotcha: byte ranges in $'…' scripts must be raw
> ([\200-\212]); double-escaping = "Invalid range end". Follow-up noted:
> fullwidth-colon (：) in the colons parser would finish uni-kv-fullwidth.
> **Now 3547 tidy, 159 ⏳** (✅ 3330 / ✅ʰ 73 / ✅ᵇ 144).

> **2026-07-12 — table chrome.** `aligned-columns` + `columnar-specs` drop
> mid-table HEADER REPEATS (token-identical to a digit-free ≥3-token header) and
> a UNITS ROW under the header (digit-free, deeper indent, fewer tokens, every
> token parenthesized/case-mixed ≤6 chars). Both rules were tightened twice by
> the golden audit (first cuts ate entr's repeated log line, consul's
> `web db allow` row, nerdctl/needrestart rows — all restored). Four
> totals-footer manifests aligned with the corpus convention (`Average:`/`TOTAL`
> row IS data — the sar-family goldens keep theirs). Closed 10 ⏳, improved 4
> covered goldens (repeated-header chrome removed). `tbl-sar-interval-repeat`
> stays ⏳ (timestamped header ⇒ headerless). **Now 3540 tidy, 166 ⏳**
> (✅ 3323 / ✅ʰ 73 / ✅ᵇ 144).

> **2026-07-12 — quoted-fields parser.** New generic `delimited/quoted-fields.sh`
> (priority 12): space-delimited positional records with `"…"`/`'…'`/`[…]`
> grouping — the access-log family (apache combined, nginx, quoted app logs,
> quoted crontabs, `lspci -mm`). Contained by: token-start-only grouping (logfmt
> and quoted CSV never match), quote-span-on-every-line signature (brackets group
> but don't qualify), ≥5 fields, spread ≤2, DNS-RR decline. Full-corpus firing
> scan: 5 ⏳ closed + exactly 3 flips, all audited improvements (lspci-mm,
> nginx-access-log-quoted, quo-haproxy-log-quoted). **Now 3530 tidy, 176 ⏳**
> (✅ 3313 / ✅ʰ 73 / ✅ᵇ 144). Gotcha: `local x="$1" y=${#x}` breaks under the
> engine's `set -u` — split declarations.

> **2026-07-12 — csv RFC-4180 quote-awareness.** One shared splitter
> (`_strat_csv_split`: quotes structural only at field start, `""` escape,
> open-field flag) now drives csv detection (top-level commas only), the header
> split (was naive `IFS=','`), the multi-line joiner (was raw quote parity —
> welded literal inch-mark rows), and the row parser; the blanket value
> quote-strip is gone (literal quotes are data). Closes 3 quoted-CSV ⏳, improves
> 12 already-covered fixtures (audited: 7 improvements, 5 faithful-neutral, 0
> regressions). **Now 3525 tidy, 181 ⏳** (✅ 3308 / ✅ʰ 73 / ✅ᵇ 144). Documented
> not-cleanly-fixable: getent-group (decline rule would flip 5 csv winners),
> quo-ssv-euro-numbers (semicolon-values is ;-dense by design). Next candidate
> parser: space-delimited quoted/bracketed-field logs (apache combined family).

> **2026-07-11 — ini-sections generic parser.** Closed the multi-section
> INI/config ⏳ cluster. `[section]` + `key = value` dumps were flattened by
> `equals` into one wide record (colliding duplicate keys); the new
> `structured/ini-sections.sh` (priority 20) emits lossless (section, key, value)
> rows. Fires only on distinct simple-token sections (ffprobe `[STREAM]`, spaced
> names, real TOML excluded). Detect guards `{`-only for JSON — a bare `_is_json`
> check treats the opening `[section]` as a JSON array (the bug that first hid the
> parser). Classifier inlined (engine unsets `_strat_*` helpers between detect and
> extract). Closes 3 ⏳, improves 9 already-covered configs (goldens re-frozen, all
> improvements, golden gate 3378/0, extract 62/62 + sample golden, smoke 49/0).
> **Now 3522 tidy, 184 ⏳** (✅ 3305 / ✅ʰ 73 / ✅ᵇ 144). Follow-up on the branch
> (rebased onto post-merge main).

> **2026-07-11 — adversarial +510 (round 2).** 510 inputs generated (8 parallel
> themed batches) to BREAK the parser across novel mechanisms: encoding/whitespace,
> Unicode display-width vs byte math, numeric punctuation, embedded-delimiter
> quoting, table oddities, nested multi-section, stacked color+box+emoji, real-tool
> exotics. **393/510 tidied with no new per-tool code (77%)** — low by design.
> The break-hunt yielded one clean format-level fix: **engine line-terminator
> normalization** (CRLF, bare-CR, VT/FF, NEL/U+2028/U+2029 → `\n`, gated, no-op on
> normal input) — fixing the cr-only/NEL/U+2028/VT/CRLF-block breakers with 0
> golden regressions. 158 inputs landed ⏳ (documented frontier: nested per-record
> sub-tables, quote-aware CSV/pipe, INI `[section]` files, Unicode-space
> separators, CJK/emoji width math). **Now 3706 tools; 3519 tidy; 187 ⏳** (✅ 3302
> / ✅ʰ 73 / ✅ᵇ 144). Golden freeze +388 new, 0 existing deleted/modified. Follow-up
> to the merged PR #35 (line-terminator fix landed there); this corpus batch is a
> fresh change rebased onto the post-merge main.

> **2026-07-11 — gap-triage.** Swept the 71 ⏳ for clean wins. Corrected the
> README's stale tier counts (1934/58/134 -> live 2915/71/139). Routed
> `vercel-list` (banner + fixed-width table `indented-hierarchy` was collapsing)
> to `aligned-columns` via a unique structural hint (`Age +Deployment +Status`) —
> new ✅ʰ. Confirmed the other tractable-looking candidates are NOT clean wins:
> banner-table siblings (`pueue-status`/`apachectl-S`) lose at detection and
> aren't banner-stripped; `lsblk-tree` can't hint without demoting generic
> siblings; `df-locale-de` is a UTF-8/mawk byte-position issue; the wide-stat
> cluster has embedded time/grouped/`|` headers. **Now 3126 tidy, 70 ⏳.** The
> one bigger lever left (risky) is refining `indented-hierarchy` to decline
> uniformly-indented flat tables — would unlock vercel/pueue-type cases but has
> a 141-tool blast radius; deferred. On PR #35.

> **2026-07-11 — gap round (ANSI strip + box-table + manifest audit).** An
> engine-level ANSI strip (once per input, gated on an ESC byte) fixed colored
> tools and cleaned 45 `*-color` goldens; `box-table` gained interior-row +
> duckdb "type row" handling (supabase / psql-unicode / duckdb). A closing
> manifest audit reclassified three fixtures that were *already* tidying but
> mis-scored — `kubectl-get-svc-none` and `lsblk-empty-mountpoint` (correct
> tables over-counted by one data row; `<none>` / empty-mountpoint cells
> preserved) and `systemctl-status-nginx` (`table`->`kv`, a single-unit status
> snapshot). No parser code changed for the three; goldens frozen and verified
> against live output. Golden gate 0 failed; **now 3196 tools; 3125 tidy; 71 ⏳.**
> On PR #35.

> **2026-07-11 — adversarial stress test (+500 hard inputs).** 500 inputs
> generated to BREAK the parser across 10 hard mechanisms. Robust to ANSI color,
> grouped headers, paragraph records, TUI bars; genuine soft spots are deep
> trees, multi-line/wrapped records, and some box-drawing dialects. Rebuilt
> `box-table` v2 (heavy/double/tabulate/dotted glyphs, interior-only rows,
> csvlook dash rule) — closed 8 box breakers and upgraded railway-variables /
> polars-describe from tokenised junk to real tables. In FULL mode 431/500 tidy;
> 69 documented ⏳. Golden gate 2952 passed, 0 failed; extract 62/62, smoke 49/0,
> melt 10/0. Now **3196 tools; 3090 tidy; 106 ⏳.** Remaining hard frontier: tree
> flattening and multi-line-record reassembly.

> **2026-07-11 — batch 3 (+539 inputs).** Third large expansion of unique
> never-before-seen tools across 10 domains (cloud/k8s/db/observability/
> networking/security/build/ML/hardware/storage). **529 of 539 (98%) tidied
> with no new per-tool code**; 10 genuine ⏳ gaps (JSON-after-comment, Unicode
> box tables, log-preamble+table, kv-ambiguous lists). Golden gate re-run clean
> (0 existing goldens changed; 529 new). Now **2696 tools; 2659 tidy; 37 ⏳**;
> golden gate 2525 passed, 0 failed.

> **2026-07-11 — segment-split cluster.** Added `_ac_split` (2-space-gap
> splitter) to `aligned-columns`, HDR-only and gated on modal-data-tokens >
> header-tokens, to close right-aligned space-in-value fixed-width tables (`ceph
> osd df`'s "1.0 TiB" under "RAW USE"). Full golden audit: `ceph-osd-df` ⏳->✅,
> 8 existing goldens improved (multi-word headers joined, space-in-value cells
> preserved), 0 regressions (a first-cut `ps-ef` deletion + 38-file over-fire
> were fixed by the modal-token gate). Now **2157 tools; 2130 tidy; 27 ⏳.**

> **2026-07-11 — multi-mode coverage audit.** Verified the corpus already
> samples multiple output modes per high-fanout tool (kubectl 54, aws 46,
> git 43, docker 28, ip 20, …); probing single-sample families for extra modes
> was ~70% collisions. Added 3 net-new generic-tidy mode samples (`pvesm-status`,
> `rbd-du`, `zk-mntr`) and tracked 2 genuine ⏳ gaps (`supervisorctl-status`,
> `ovs-ofctl-dump-flows`) in the existing hard classes. Rejected `ceph-osd-df`
> (shape-passes but data is misaligned garbage) rather than inflate coverage.
> Now **2156 tools; 2129 tidy; 27 ⏳.** Golden gate: 1995 passed, 0 failed.

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


## Corpus size + gaps (2151 inputs, 25 ⏳ as of 2026-07-10)

The corpus grew in two +500 expansions of unique never-before-seen tools
(0 basename overlap each): **1040 → 1540 → 2040**, a **+99 benchmark-tool set**
(2040 → 2139) covering every benchmarking domain, and a **full-range fio
expansion** (2139 → 2151 — 12 distinct fio output modes vs the previous 2).
Each batch generalized at ~92% with **no new per-tool code** (batch 1: 466/500;
batch 2: 461/500; benchmarks: 94/99). Format-level capability added over the
rounds: melt long-form for lone kv pairs, a `go-struct` parser, text-lines gate
fixes, a rebuilt aligned-columns header-promotion heuristic (value-token
contrast, styled all-text headers, 2-column value tables, chrome dropping — 41
of the earlier 67 ⏳ closed), a `delimited/pipe-table` parser for GitHub-flavored
markdown tables (BenchmarkDotNet), **headerless numeric CSV** in
`structured/csv` (data loggers with no header row — fio `--write_bw_log` /
`--write_iops_log`, `sar -o`, collectd; first-row-all-numeric ⟹ no header), and
two parsers that fully closed fio's non-tabular sections: `delimited/semicolon-
values` (fio terse v3/v5) and `delimited/labeled-inline-kv` (`label: k=v, k=v`
records — fio disk-stats/run-status/io-depths/latency-dist).
Coverage is now **2126 / 2151** (✅ 1934 / ✅ʰ 58 / ✅ᵇ 134); golden regression
1980 pass / 0 fail / 0 deleted; holdout 68/68.

fio is now fully handled: of its 12 output modes glean tidies 9 (json, bw-log,
iops-log, terse-v3/v5, disk-stats, io-depths, run-status, latency-dist) and
treats 3 as loose text (normal-full / multijob / status-line are nested reports,
not single datasets).

The 31 ⏳ left include 5 fixed-width benchmark tables (stream-benchmark,
kdiskmark-run, pytest-benchmark, lzbench-run, blender-benchmark) — a title
banner + multi-word header over a whitespace grid. A dedicated `banner-fixed-
table` strategy was prototyped (tidied stream + blender cleanly) but its detector
grabbed 26 existing inputs — the shape is indistinguishable from headerless
word-data lists (`vagrant status`), single-space headers (`netstat -rn`), and
`key: value` blocks (`ceph status`) — so it was dropped. The principled fix is
positional multi-word-header handling in `aligned-columns` (a real improvement —
reunites `Depended_by`/`NOMINATED_NODE`/`Flags_Mask` across ~60 tables) but it
changes 69 goldens and needs a full audit round. The rest of the tail:
- **multi-line / banner-entangled headers** (numastat-p, quota-report,
  vnstat-hourly, frr-show-bgp-summary, sar-cpu, gluster-volume-status,
  watch-diff, stream-benchmark, kdiskmark-run, pytest-benchmark) — the header
  spans 2 ragged lines or shares its token count with a banner, so no
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
bash tests/corpus/run.sh --golden   # corpus regression (1980 goldens, non-CI)
bash tests/corpus/run.sh --coverage # regenerates COVERAGE.md
bash tests/corpus/holdout/run.sh    # generalization check on unseen output
```

`smoke.sh` is hermetic — it clears the caller's `GLEAN_*` env (notably
`GLEAN_HOME`) so a stale `~/.glean/extract` engine can't shadow the bundled one
and skew classification. If a real `glean` run misclassifies, check
`glean doctor`: it warns when the extract engine came from a `GLEAN_HOME`
override rather than the bundled tree.
