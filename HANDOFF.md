# Handoff — provost

## 2026-08-20: bundle drift is now CI-enforced — the manual checks below are obsolete

The entry below records two bundle traps and recommends running a parity
check by hand. That check is now a CI job, so it no longer relies on anyone
remembering: `tests/check-bundle-current.sh`, wired into
`.github/workflows/ci.yml` as the `bundle` job. It fails the build on any of
three drifts, naming the offending paths and printing the fix:

- **stale list** — a merge added files and the bundle was not rerun;
- **junk** — `merge.sh` swept up untracked build artifacts, since it bundles
  the working tree rather than the index;
- **stale content** — a tracked file was EDITED after bundling, so the file
  list still matches and only the bytes differ. This is the everyday case
  (edit a doc, forget to regenerate) and a file-list comparison misses it
  entirely; the check compares the sha256 that `merge.sh` records in each
  `===META:` line against the file's real hash.

**What this means in practice:** you no longer need to remember to regenerate
the bundle. CI will tell you, by name, the moment it drifts. When it does:

```bash
git clean -Xdn                                       # review gitignored junk
git clean -Xdf                                       # remove it
bash ../shared_tools/scripts/merge.sh bundle.txt .   # regenerate
bash tests/check-bundle-current.sh                   # confirm
```

The `git clean` step is not optional ceremony — skipping it is exactly how
`.coverage` / `.pytest_cache/` / `__pycache__` ended up inside the bundle
once already.

## 2026-08-20: bundle.txt regenerated — current with #66

#65 regenerated `bundle.txt` immediately before #66 landed, so the bundle was
short by exactly the 36 files #66 added. Rerun and verified: 12,248 entries,
12,248/12,248 checksums OK on the `split.sh` round-trip, `diff -r` of the
expansion byte-identical against the working tree, pure printable ASCII, 0
`node_modules` file sections.

**Two traps worth knowing before the next regeneration:**

1. **`merge.sh` bundles the working tree, NOT `git ls-files`.** My first
   attempt swept in `.coverage`, `.pytest_cache/` and three `__pycache__/*.pyc`
   files left by an earlier `python -m pytest` run — all gitignored, so
   `git status` was clean and nothing warned me; four of them landed as
   base64 binary sections. Regenerate from a clean tree (`git clean -Xdn`
   first to see what's there), and verify parity rather than assuming it:
   ```bash
   diff <(grep '^===FILE' bundle.txt | sed 's/^===FILE[^:]*: //; s/===$//' | sort) \
        <(git ls-files | grep -v '^bundle.txt$' | sort)
   ```
   That check is what caught it, and it is cheap enough to run every time —
   or to wire into CI, which would make this whole class of problem
   self-reporting.

2. **`grep -c node_modules` is the WRONG staleness/cleanliness check** and
   looks alarming for no reason: it currently returns 44 while the number of
   actually-bundled `node_modules` files is 0. The 44 are the string
   appearing inside `.gitignore`, changelog prose, and npm/yarn corpus
   fixtures. Grep for `^===FILE.*node_modules` instead.

Also worth noting: the bundle goes stale on *every* merge that adds files, and
the two most recent regenerations have both been "regenerate, then immediately
merge something else". Regenerating as the last step before merge (or the CI
check above) would break that cycle.

## 2026-08-20: four-tool output coverage (iperf / mx / binnacle / doehelper) — DONE

User asked provost to parse **all** output — commands *and* file artifacts —
from four sibling tools: `iperf_orchestrator`, `matrix_orchestrator` (`mx`),
the eight `binnacle` tools, and `doehelper` (`doe`). All four repos are
cloned read-only under `/workspace/martingallagher-code/`.

**Method that mattered:** rather than trusting the repos' docs, I `pip
install -e`'d all four and ran them for real in this container — including a
complete DOE session end-to-end (scaffold -> generate -> 12 real runs ->
analyze) and a synthetic iperf run built from realistic log fixtures. Three
separate source-level surveys of the repos confirmed the docs are drifted or
absent in many places (iperf's README documents a 16-column results CSV that
is really 19; two artifacts it documents are never written at all; doe has
essentially zero captured output anywhere). **Real output found a bug the
documentation samples could not** — see the healthy-box entry in CHANGELOG.

**Already covered, verified against real captures, no new code needed:**
every CSV/TSV artifact across all four tools (binnacle's shared
`host,ts,rule_id,...` diagnostic CSV, `reachable`/`logtriage`/`netmesh`/`mx`
report + grid CSVs, `doe export-data` in both CSV and TSV, iperf's real
19-column `iperf_results.csv`), every `--json` output, and — only because of
the `#`-comment CSV fix landed the day before — `mx`'s `matrix.csv`,
`netmesh`'s `mesh.csv`, and `iperf`'s `--grid` plan file.

**Six new strategies this round** (each with a real captured sample + frozen
golden): `gnu-version`, `doe-analyze`, `doe-info`, `iperf-pivot`,
`iperf-summary`, `fleet-host-lines`. Plus the `binnacle-severity-report`
priority fix. Details per strategy in CHANGELOG 2026-08-20.

`gnu-version` is the widest win: all five tools (provost included) print the
same 5-line GNU `--version` banner, and it previously parsed as nothing at
all (`unsorted`, confidence 35). It is written generically, so real GNU
tools (`grep`, `sed`, `ls`, `tar`, `make`, `bash`) parse too, while
`python3 --version` correctly declines.

**Verification:** smoke 65/65, melt 10/10, extract suite 63/63 test files,
corpus `--golden` 3470/0 (the baseline, unchanged), self-validation 254
total / 206 pass — exactly +6/+6 over the pre-round 248/200, nothing else
disturbed.

**Correction, second pass:** an earlier version of this entry claimed the
five secondary `doe` reports could stay on `block-records` because it
"captures their content". That was asserted from their general shape, not
checked — and on inspection it held for only ONE of them. `doe power` was
dropping its entire per-factor table, `doe status` was turning twelve runs
into twelve columns of a single row, and `doe optimize` was doing the same to
every RSM coefficient. All three now have strategies (`doe-power`,
`doe-status`, `doe-optimize`; CHANGELOG 2026-08-20). Only `doe suggest`
genuinely loses nothing and stays on `block-records`. Worth remembering as a
general lesson: "the generic catch-all handles it" is a claim to verify by
looking at the emitted table, not to infer from the input's shape.

**Known remaining gaps, deliberate:** `doe suggest` (above — no data lost),
`doe optimize`'s `--multi` / `--steepest` variants (not captured; they need
flags this session's sample config did not exercise). Also unparsed by
design:
prose blocks (`WHAT TO DO NEXT`, `mx hints`' cheatsheet, binnacle's
EVIDENCE/RESOLVERS/TIMELINE sub-sections) and the two "hybrid" doe CSV
exports (`achieved_power_*.csv`, `cross_validation_*.csv`) whose
`__summary__` sentinel rows mix long and wide layouts in one file. Any of
these is a clean next slice — same pattern: capture real output, write the
strategy, freeze a golden, corpus-regression it.

**Process note for whoever runs the next multi-agent round:** do NOT have
each subagent run `tests/corpus/run.sh` independently. Seven concurrent
corpus sweeps on this 4-core box drove load to ~30 and turned a ~4-minute
check into ~50 minutes; one agent killed another's run trying to clean up.
Have agents skip it and run ONE consolidated corpus check serially at the
end, which is what finally produced the 3470/0 above.

## 2026-08-20: `iperf-pivot` + `iperf-summary` strategies — DONE

`iperf-orchestrator`'s two report commands now have bespoke strategies, both
under `extract/strategies/network/` at priority 21 / confidence 88:

- `iperf-pivot.sh` — `make-pivot`'s ASCII throughput matrix. One row per
  measured `(source, target)` cell (`entryN.source/target/mbps`); `-` and
  `-(N)` cells are SKIPPED, so `total_entries` counts measured directions
  only. Broadcast: `run_at`, `mode`, `duration_s`, `port`, `parallel`,
  `n_hosts`, plus `fleet_mbps`/`fleet_gbps` from the trailing Fleet line.
  The per-host bar chart and preamble prose are out of scope.
- `iperf-summary.sh` — `results-summary`'s "Slowest N" list
  (`entryN.mbps/source/target`) with `n_directions`, `n_errored`, `min_mbps`,
  `p50_mbps`, `mean_mbps`, `p95_mbps`, `max_mbps` broadcast. `What next:`
  prose is out of scope.

Samples: `extract/samples/iperf-{pivot,summary}/basic.txt`; goldens frozen in
`extract/tests/golden/iperf-{pivot,summary}.txt`.

Verified: 3 entries each (hand-checked), auto-detect picks each strategy at 88,
`validate-strategies` PASS at 75, corpus golden 3470 passed / 0 failed
(unchanged baseline).

Possible next step: neither strategy reads the pivot's per-host incoming
bandwidth bar chart or the `mean per-host throughput` half of the Fleet block —
both were scoped out. If a second dataset per input is ever wanted, that is
where to start.

## 2026-08-20: `gnu-version` strategy — DONE

`extract/strategies/misc/gnu-version.sh` (new, priority 22, confidence 85)
parses the GNU-style `--version` banner that every tool in the suite prints
(`provost`, `mx`, `doe`, `iperf-orchestrator`, `why-slow`), which previously
fell through to `unsorted` at 35. One wide record: `tool`, `version`,
`copyright`, `license`, `license_url`, `warranty`, `author`. Written to the
GNU coreutils convention, not to this suite, so `grep`/`sed`/`ls`/`tar`/
`bash`/`make --version` parse too; `python3 --version` (no copyright/license)
correctly declines.

Samples in `extract/samples/gnu-version/` (5 files, `basic.txt` declared),
golden in `extract/tests/golden/gnu-version.txt`.

Verified: 5/5 samples auto-detect `gnu-version` at 85 and extract correctly,
`validate-strategies -s gnu-version` PASS, corpus golden regression
3470 passed / 0 failed (unchanged).

Next step if anyone wants it: `gnu-version` sits at 85, below the generic
`pkg-config` strategy at 88, so for real GNU banners with a `name: value`-ish
shape (`ls`, `sed`, `tar`, `make`, `bash`) `pkg-config` still takes the primary
slot and `gnu-version`'s fields are merged in alongside it. Bumping
`gnu-version` to 89 would give those the clean single-record parse; it is
corpus-safe (no corpus input matches `gnu-version` at all) but was left alone
as an out-of-scope behavior change.
## 2026-08-19: bundle.txt regenerated — current with #63 and #64

`bundle.txt` had fallen behind the tree (the mx/binnacle strategies and the
Meridian Commander browser docs landed after the last regen), so it was rerun
the standing way — `bash ../shared_tools/scripts/merge.sh bundle.txt .` from
the repo root (shared_tools now clones to `/workspace/shared_tools`; adjust
the path to wherever it lives). 12,212 entries, round-trip verified with
`split.sh` (all checksums OK, `diff -r` byte-identical), 0 `node_modules`
sections. Three practical notes for next time: write the CHANGELOG/HANDOFF
entries BEFORE regenerating, so the bundle carries them (regenerating after a
doc edit leaves the bundle one step behind the tree); the run takes ~6 minutes on this
tree (the delimiter derivation scans all content first), so give it a generous
timeout; and its `bundle.txt.tmp.*` working files are transient — never commit
them, they vanish when the run finishes. Next steps: none; rerun after the
next tree change.

## 2026-08-19: matrix_orchestrator + binnacle output coverage — DONE

User asked for two things: parse `go test -v` output, then make sure
provost can parse *all* output from two sibling tools, `matrix_orchestrator`
(`mx`) and `binnacle` (8 diagnostic tools). Both repos cloned read-only at
`/workspace/martingallagher-code/{matrix_orchestrator,binnacle}`. Surveyed
both for real/literal example output (README/docs/tests — binnacle has a
"What it looks like" example per tool in `docs/tools/*.md`; mx's examples
came from actually running the installed CLI locally). Asked the user
scope ("full sweep now" vs. highest-value slice vs. pick-per-tool) given
the size that turned up — they chose full sweep.

**7 new strategies, 1 generic-parser fix, all done and verified:**

- `extract/strategies/build/go-test.sh` — `go test -v` (the original ask).
- `extract/strategies/system/binnacle-severity-report.sh` — covers 4 of
  binnacle's 8 tools at once (why-slow/resolve/during/skew all share one
  VERDICT/CRITICAL/WARN/ok report shape).
- `extract/strategies/misc/binnacle-agree.sh` — `agree` (GROUP blocks).
- `extract/strategies/network/binnacle-netmesh.sh` — `netmesh summarize`
  (WORST PAIRS table).
- `extract/strategies/misc/binnacle-logtriage.sh` — `logtriage` (ranked
  `#N` template entries).
- `extract/strategies/network/binnacle-reachable.sh` — `reachable`
  (rewritten server-list file, `#[unreachable]` tags).
- `extract/strategies/network/mx-summarize.sh` + `mx-check.sh` — `mx`'s
  two stats-report commands.
- `extract/strategies/structured/csv.sh` — generic fix: tolerate a
  leading `#`-comment header (covers `mx gen`'s `matrix.csv`, haproxy's
  `#`-prefixed header convention, and correctly still declines Prometheus
  exposition format). See its own CHANGELOG entry for the three-iteration
  story — the naive version broke 4 existing corpus tools before landing
  clean.

All 7 strategies: built by parallel subagents (each independent, no git),
verified against real/documented sample text — both forced `--strategy`
and unassisted auto-detection — plus `validate-strategies` PASS and a
frozen golden per strategy. The csv.sh fix and each new strategy were then
checked against the full `tests/corpus/run.sh --golden` (3470/3470,
matching the pre-change baseline exactly) and `extract/tests/run_tests.sh`
(all green) before anything was committed — see CHANGELOG 2026-08-19 for
the detailed per-strategy writeups.

**Not covered, by explicit design choice per the strategy prompts, not an
oversight:** the EVIDENCE/RESOLVERS/NAMES/TIMELINE/SHARES sub-sections and
`WHAT TO DO NEXT` prose blocks inside the binnacle reports; `mx doctor`,
`mx hints`, `mx status`/`start`/`stop`/`run` (no literal output samples
existed anywhere in the mx repo for these — only substring test
assertions, confirmed by survey); binnacle's `--csv` export flag's own
output format (not surveyed). If any of these turn out to matter, they're
the natural next slice — same pattern (real sample → strategy → golden →
corpus-regression-checked).

## 2026-08-19: a TUI browser for the store now exists (in Meridian Commander)

Meridian Commander's new **Provost data** plug-in browses a provost store
read-only — datasets as tables, the capture log, row → source provenance —
by reading the store's plain files (`datasets/*.tsv`, `captures/<id>/`,
`provenance.tsv`, found via `.provostrc`/`CONTROLLED`) through its own
filesystem layer, locally or over SFTP/SSH. This repo only gained a README
pointer (end of "Integrating from another tool"); the plug-in itself lives
in `meridian_commander/plugins/provost_browser.py` over there. Implication
for future changes here: the store's on-disk layout and those marker files
are now read by an external tool, so renaming/moving them should update that
plug-in in the same breath. Next steps: none in this repo.

## 2026-08-19: released v2.0.1 — the BOM fix is now on PyPI

The 2026-08-18 BOM fix merged to `main` but PyPI still served 2.0.0 (built
before the fix), so `pip install provost` users were unaffected by it.
Bumped `VERSION` to `2.0.1`, tagged `v2.0.1`, and triggered `release.yml` to
publish. `pip install provost` now gets the fix. No further action needed
unless a fresh regression turns up.

## 2026-08-18: fixed — BOM-prefixed JSON piped into provost was failing to parse

User report: "provost is failing to parse a simple json file that is pipe
in." Root cause found and fixed: a leading UTF-8 BOM (as commonly written by
Windows tools — PowerShell `Out-File`, Notepad's "UTF-8" encoding) defeated
the exact-prefix `{`/`[` checks in the `json`, `json-array`, and `jsonl`
strategies' `strategy_detect`, so BOM'd JSON silently fell through to the
`unsorted` dataset as raw undecoded bytes instead of a tidy table. Fixed by
stripping the BOM in each of those three `strategy_detect` functions before
the prefix check — mirroring the BOM-strip `csv.sh` already had. See
CHANGELOG 2026-08-18 for the byte-level verification. All required suites
green: smoke 65/65, melt 10/10, extract 63/63 test files.

Next steps: no other JSON edge case surfaced in a broad sweep (nested/
ragged/unicode/no-jq-on-PATH/pretty-vs-compact/scalar-arrays/empty
objects-arrays all already worked correctly pre-fix) — this looks like a
complete fix for the reported symptom, not a partial one. If the user's
original failing file differs from a plain BOM case, get the actual file
(or `xxd`/`od -c` of its first ~16 bytes) to confirm before assuming this
was the only cause.

## 2026-08-18: `--version` brought in line with the rest of the provost suite

`provost --version` was a bare `provost 2.0.0` — every sibling tool
(binnacle, design_of_experiments, iperf_orchestrator, matrix_orchestrator,
meridian_commander, phone_a_friend) prints a five-line GNU-style block
(version / copyright / license / free-software / no-warranty), and those
tools' own copyright/license lines were also inconsistent with each other
(some said "Martin Gallagher", some "NO WARRANTY" in caps, differing
license-line wording). All seven were normalized to the same layout, name
"Martin J. Gallagher" everywhere, lowercase "no warranty"; provost's license
line correctly says `GPL-3.0-only` (its real SPDX license) rather than the
`-or-later` the other tools use. Only `provost` (this repo) needed a code
change here — see CHANGELOG. Smoke suite (65/65) green after the change.
Next: nothing outstanding from this change.

## 2026-08-14: the tool is now **provost** (was glean), v2.0.0, PyPI- and RTD-ready

- Command `provost`, env vars `PROVOST_*`, store `~/.provost` / `./.provost`,
  marker `.provostrc`. No compat aliases — clean break at a major version.
- PyPI distribution name **`provost`** (owner holds it; import package stays
  `provost_data`). `provost --version` reads the top-level VERSION file, so
  CLI and wheel cannot disagree. sdist+wheel built, `twine check` PASSED,
  clean-venv install verified end-to-end (capture → ls).
- Read the Docs: `.readthedocs.yaml` + `mkdocs.yml` (readthedocs theme) over
  `docs/`, new `docs/index.md` + `docs/usage.md`; `mkdocs build --strict`
  clean. Create the RTD project pointing at this repo and it builds as-is.
- NOT renamed: fixture data that merely records the word "glean" (corpus
  inputs/goldens, extract samples) and the `envoy-*` internals. The GitHub
  repo itself **has now been renamed** to `MartinGallagher-code/provost`
  (redirects keep old remotes working; sweep any remaining `glean` URLs in a
  follow-up).
- To publish: `git tag v2.0.0` + GitHub release triggers `release.yml`
  (Trusted Publishing). **Blocked until a one-time manual fix on PyPI**: the
  trusted publisher was registered against repo `glean`, and the first
  release run failed the OIDC exchange with `invalid-publisher` because the
  token now says `repository: MartinGallagher-code/provost`. On
  https://pypi.org/manage/project/provost/settings/publishing/ update (or
  re-add) the publisher to: owner `MartinGallagher-code`, repo `provost`,
  workflow `release.yml`, environment `pypi` — then re-run the release
  workflow (workflow_dispatch works; no need to re-publish the GitHub
  release).

## Where we actually stand: the benchmark's nine clusters are WORKED (2026-08-13)

`tests/benchmark/` (50 held-out inputs, rated 23/12/15 on 2026-08-12) drove a
"fix it all" round. The set now re-scores **40 PASS / 9 PARTIAL / 1 FAIL** —
but read the caveat in `ratings.tsv`: **these 50 are no longer unseen.** The
engine was tuned against them, so they now measure regression, not
generalisation. The next generalisation number needs a fresh 50 nobody has
parsed. Full defect analysis of the original run:
`docs/benchmark-2026-08-12-generalisation.md`; what changed:
CHANGELOG 2026-08-13.

The two big engine mechanisms that round added, and their sharp edges:

1. **Truncation guard** (`_discovery.sh`, `_parse_is_truncated`): a parse
   much smaller than its input AND blind to most of its lines loses its claim
   and the next strategy runs. Exempt: hint-routed strategies, `-s`,
   `--replay`, and json/yaml/xml/toml (structured grammars are authoritative
   and legitimately compressive — the first cut left nested-JSON caddy-adapt
   EMPTY, which is the failure mode to keep in mind when touching this).
2. **Offset assignment** (`aligned-columns.sh`): sparse tables (data rows
   shorter than the header) assign values by header character spans. It
   WITHDRAWS unless >=80% token-span overlap and >=60% exact edge alignment;
   the edge gate is what keeps prose-under-a-fake-header (deno-lint) out.
   When extending it, re-check deno-lint-summary, chrony-sources, ceph-osd-df
   (must NOT claim: its multi-word cells belong to seg-split), and the
   tbl-empty-*/tbl-sparse-* fixtures.

Still open from the benchmark, deliberately:
- 37 (`###`-decorated table): default mode still shreds the banners; --multi
  segments it correctly. Fixing default would mean DELETING banner text.
  The real fix is segmentation-closer-to-default, which is a design decision.
- 16 (vmstat group header): prefixing unique HDR2 names would rename every
  vmstat column; reviewer ruled the current shape right. Kept.
- The ~200 corpus goldens regenerated this round were triaged by census +
  sampling, not read line-by-line — the recurring find was goldens that had
  been RECORDING defects (tbl-empty-label-col held sizes under LABEL,
  useradd-defaults lacked its EXPIRE row, chrony one column left). If the
  reviewer disagrees with any regenerated golden, the marks workflow catches
  it next round.

## Status: **--multi is a scored search over four candidate segmentations** (extract/lib/_score.sh: coverage + tidiness). The candidates are the rule-proposed split, the same split with block-grouping's shape tolerance off, that split with a `#` legend folded in as the following block's header, and the whole input unsplit. The two refinements compete for the split slot and need only TIE; the winner then faces the whole-input veto (vetoed only when whole is >2% better). Coverage now counts field NAMES as well as values — a header word promoted to a column name survived, and not counting it ranked naming a column below dumping the header as prose. All reviewer-ruled cases resolve correctly: kubectl 1, iostat-x 3, proc-slabinfo 1 (legend folds in, columns named), 7z 3, artillery 3, cargo-bench 3, cargo-test-summary 3, atlantis 3; aureport now yields `num/date/time/acct/host/term/exe/success/event`. tests/corpus/coverage.sh ranks the corpus by how much of each input survives its parse (a review SIGNAL, not a gate). Validated 409.

**Test harness was lying and is now fixed** (`extract/tests/helpers.sh`): `run_test` ran each test as `( set -e; "$func" ) || result=$?`, and a command on the left of `||` has `set -e` suppressed for its whole body, so a test whose assertion failed kept running and reported PASS. Assertion failures are now recorded in a file that crosses the subshell boundary; `expect_assert_failure` is the escape hatch for helpers that test helpers. The iostat mis-grouping this release fixes had been failing inside a "passing" test, and **nine further stale expectations** surfaced and were cleared — see CHANGELOG. Treat that as the standing lesson: before this, a green extract suite did not mean what it said.

**ASCII-art gutter strip landed** (`extract/lib/_helpers.sh`): cilium-status's hexagon logo is no longer part of its keys. Byte-oriented so the U+00AF glyph is matched exactly; fires on exactly 1 of 3,705 corpus inputs.

**Round 18 is now worked through.** Data loss cleared: biosdecode (9% -> 98%), clpeak-run (45% -> 100%), btrfs-filesystem-show (36% -> 88%), cilium-status, R-sessioninfo, cheat-sheet (was losing one of its two commands), amdgpu-top (was seven verbatim lines). Granularity cleared: apk-info-a (package name factored out of every key), bundle-outdated (all five columns, not three), aureport (named columns). Two new hint-routed strategies: `subject-field-value` (p46) and `super-header-table` (p45).

**Round 19 (26 marks on the fresh workbook) is part-worked.** DONE: the eleven AWS `table` outputs, fixed in the SCORER rather than a parser — default mode was already right and the shredded `--multi` split was simply outscoring it, 9705 to 9333, because nothing charged cells that were only `|`. A delimiter-only cell is now a tidiness defect; 23 of 68 measured inputs improved, none regressed. OPEN, in rough order of cluster size: prose being columnised (#3 R-sessioninfo, #4 R-version, #9 arp-scan, #11 artillery-report, #12 atlantis-status — "a series of line-long statements, not multiple fields"); a header row not applied to its table (#6 ansible-galaxy-collection-list, #13 aureport-login, #15 autocannon-run); first-line loss (#7 ansible-galaxy-list, #10 arping); 7z-benchmark's Compressing/Decompressing super-header (#1); apachebench's missed median column (#8).

**The score has now twice preferred a destructive parse** — arp-scan, and these ASCII boxes — both times because recovering a couple of decoration lines outweighed wrecking a table. Coverage dominating tidiness is systematically too generous to parses that keep frame junk. Reweighting is a better next move than more parsers.

**cassandra-nodetool-tpstats (#41, a genuinely lost line) was attempted and reverted.** The caption `Latencies waiting in queue (micros) per dropped message types` sits in the same block as the table below it, and the table parser takes the NEXT line as its header and drops the caption. Peeling it works — and note the second half of the trick, which is not obvious: a caption detects as no strategy, and grouping's "a nameless block joins the open group" rule puts it straight back into the table above, so it has to be pushed as an explicit `text` block to survive.

It was reverted because the boundary rule fires corpus-wide and PRE-EMPTS strategies that understand a whole block: clpeak-run lost its section names (clpeak-run 95 -> block-records 60, undoing today's 45%->100% fix) and amdgpu-top's single grouped dataset shattered into three. One mark fixed against two regressions, plus five more changes unverified. The rule needs to know whether a bespoke strategy already claims the block, which is detection information a boundary rule does not have — the same root problem as arp-scan. Do NOT retry it as a pre-extraction rule.

**THE PROSE CLUSTER IS BLOCKED, AND ON A KNOWN CAUSE.** Seven marks say "should not be separated into columns" (#3 R-sessioninfo, #4 R-version, #9 arp-scan, #11 artillery-report, #12 atlantis-status, #30 bpftrace, #37 cargo-bench). Detecting prose from SURFACE FEATURES before extraction was tried and reverted: it turned R-version's structured parse into three verbatim lines and atlantis's `dir:`/`workspace:` records into text. That is the decide-before-detection mistake the scoring architecture exists to retire, and it will misfire again on any input that parses well.

The real blocker: **the score cannot see shredding.** `Ran Plan for 2 projects:` sliced into five columns A..E scores a PERFECT 10000 — every token present, no defect fires — so the score picks it over keeping the sentence. Three separate clusters now sit behind this: the prose marks, arp-scan, and the ASCII boxes (the last fixed only by a targeted delimiter-cell defect). Do the reweighting deliberately — give tidiness real weight against coverage, and add a defect for one-word-per-column shredding — before attempting the prose cluster again. What IS in place: a verbatim `text` cell is exempt from tidiness charges (atlantis was docked for keeping `Plan: 2 to add, 0 to change, 0 to destroy.` intact), measured at 0 of 83 changed, so the scorer will not fight the eventual fix.

**Two known gaps in the test harness itself**, both worth fixing before trusting a green run further:
1. **Hint-only strategies have vacuous goldens.** `verify_strategy_outputs.sh` drives each strategy with `-s NAME`, but `-s` still runs `strategy_detect` — which a hint-only strategy defines as "always return 1". So every such strategy (nested-colon-kv, subject-field-value, super-header-table, and ~12 others) records an EMPTY golden and has no regression protection from that harness. They are covered by the corpus gate, which does honour hint routing under `--generic`, so this is a second line of defence rather than none. The fix is to let an explicit `--strategy` override detection — the explicit request IS the detection, exactly as a hint row is.
2. `--multi` has no corpus gate at all. Every `--multi` change is guarded only by the 14 checks in `test_multi_mode.sh`.

**Round-18 data-loss marks cleared:** biosdecode (2.0, every entry-point block as section/key/value — was SMBIOS only), R-version 1.1 (`Running under:`), btrfs-filesystem-show 1.1 (label/uuid/totals carried onto each device row), cilium-status (art gutter).

Open: clpeak-run still loses its `Global memory bandwidth (GBPS)` / `Single-precision compute (GFLOPS)` section names — `block-records` wins and the sections have no trailing colon, so `nested-colon-kv` (whose header rule requires one) does not fit; the contained fix is to let a colon-less line count as a header when the line after it is MORE indented, plus a hint row for clpeak, then re-verify the four tools already routed to that strategy. **arp-scan: do not retry the prose peel without fixing detection first** — peeling the preamble works, but it removes the literal `arp-scan` string the columnar spec detects on, so the table degrades to A/B/C/D with `Netgear Inc.` split in two, and the score PREFERS that (7097 vs 6842). Per-block detection needs to see the whole input as context. aureport-login's legend is two names short of its rows (fixture legend genuinely omits two columns) so it stays prose; data loss (biosdecode, R-sessioninfo, btrfs, clpeak-run, arp-scan — note the coverage percentages in earlier entries predate the field-name fix and now read higher); granularity/super-headers (apk-info-a, cheat-sheet, amdgpu-top, cargo-machete, bundle-outdated, cargo-audit, blackbox-probe); workbook entries 41-100 unreviewed; netperf-tcp shape genuinely ambiguous.

**CI note (2026-08-06):** GitHub Actions had a multi-hour action-resolution outage ("Failed to resolve action download info: Service Unavailable") failing every job before any code ran. All suites pass locally; re-run the workflows once GitHub recovers. Round-13/14 hard shapes also still open.

> **2026-08-04 — round-11 marks: all 12 fixed.** version-line 1.1 (Prometheus
> `NAME, version X (branch: …)` → named columns; tempo/thanos + loki/mimir/ghc
> riders), dotted-kv-tree p31 (cgget family — reviewer's exact key/subkey/value
> spec; lowercase-dotted key gate, NN:NN linter-coordinate veto), probe-verdict
> p37 (chkrootkit `name | result`), engine color-as-separator recovery (SGR-only
> column boundaries → TAB, gated on no-2+-space-run per line; cmb-colorsep pair
> recovered, mid-cell recolors/gauges/boxes untouched), and five narrow p39
> strategies (cipher-suites, plan-actions, result-blocks, decorated-groups,
> arrow-info-records) for the singleton shapes. 4 goldens net ADDED
> (cmb-colorsep ×2, sslscan, terraform-plan), 0 deleted. First cuts stole
> 18 (dotted keys) / 8 (empty-indent lead) — both gated to zero. Gate
> 3459/0/246; review-output refreshed (15 changed, all intended).

> **2026-08-04 — multi-dataset extraction (`--multi`).** The reviewer's
> "one input may deserve multiple outputs" note is an engine mode: blank-line
> block split → detect-only pass per block → group consecutive blocks sharing
> winner name AND shape (modal token count ±1) → full pipeline per group →
> datasets emitted behind `__DATASET__ n strategy confidence` separators.
> iostat -x → 3 datasets (banner, avg-cpu kv, Device table) — nothing
> dropped; blank-separated record streams re-form into one. New
> test_multi_mode.sh (extract 63/63). Capture-pipeline adoption + a corpus
> `multi` kind are scoped in docs/0003-multi-dataset.md, not started.

> **2026-08-04 — round-10 complete (npm-audit + kubectl-describe).** New
> `headline-kv-blocks` p36: npm audit's advisory blocks (`name  <range>`
> headline + `Severity:` kv + `Title - URL`) → name/A/Severity/B/C/detail —
> the "missed columns" all recovered. New `describe-report` p21: kubectl
> describe's aligned kv (+continuations `; `-joined) + `Section:` tables
> sliced at their `----` separator positions (overflow-safe boundary walk) →
> one record per Conditions/Events row with kv carried; 5 sibling describes
> improve free (events had been welded into COLUMN NAMES). Gotcha refound:
> `local x="$1" y=${#x}` breaks under `set -u` — split declarations. Gate
> 3455/0/250, 0 deleted.

> **2026-08-04 — nst-python-traceback-log (bracket-log 1.1).** Non-bracketed
> continuation runs (first line indented or colon-terminated — a Python
> traceback under its ERROR line) absorb into the entry above as a `detail`
> column, `; `-joined. Pure 80%-bracketed logs unchanged; bare `[tag]` spacer
> lines skipped (mvn byte-identical). Free rider: wpscan-summary blob → 3
> records. Gate 3455/0/250, 0 deleted.

> **2026-08-04 — CR-redraw preprocessing + box-dag.** Engine: `\r`-redrawn
> progress lines are transient chrome — interior-`\r` lines whose first/last
> segments share a ≥8-char prefix are DROPPED (kept collapsed-to-final when
> they are all the input has); pre-baked welds (CRs consumed upstream, `%]`
> gate, first-12-chars-recur signature) get the same rule after the ANSI strip.
> Zero collateral over 3705 inputs; cmb-cr-redraw-progress-final now yields its
> real `LAYER | COMMAND | SIZE | CACHED` table. New `box-dag` p30: dvc dag's
> ASCII-boxed pipeline → one `stage` row per box; interior `|` (real box
> table) rejects. Gate 3455/0/250, 0 deleted.

> **2026-08-04 — decode-dimms / btrfs / hugo / go-ycsb (four strategies).**
> `banner-sections-kv` p45 (+`---=== ` hint): dash-wrapped section banners over
> tab-kv pairs → group|key|value (decode-dimms 14 rows). `inline-kv-groups`
> p39: inline `k: v` headers over word-run→value members → header pairs
> carried onto per-member rows (btrfs fi show — devid rows recovered).
> `version-line` p44: single-line `name vX.Y.Z …` banners → name|version +
> named `k=v` columns (hugo, dagger); the over-broad cargo-tree hint narrowed
> to require `├──`/`└──`, releasing tinymembench + y-cruncher to real parses
> and improving 17 version-tool goldens (name/version named columns).
> `dash-labeled-stats` p42: `NAME - k: v, k: v` records → name + per-key
> columns (go-ycsb). Gate 3454/0/251, 0 deleted; extract 62/62, smoke 58/0.

> **2026-08-04 — `sdparm-all` (sectioned-fields).** New generic
> `sectioned-fields` p46. Colon-terminated section header → carried `group`
> column; indented `NAME value [cha: y, def: N]` field rows → `name | value` +
> the trailing bracket decomposed to `cha | def`; leading device line drops as
> a comment. The reviewer's "Read…/Caching… repeated column values, items below
> in multiple columns." Auto-detect (before aligned-columns): members MUST end
> in a `[key: value, …]` bracket and no unclassified line may follow a header —
> zero blast radius. Manifest `kv - 4` → `table 10 5`; golden regenerated. Gate
> 3452/0/253, 0 deleted; extract 62/62, smoke 58/0.

> **2026-08-04 — round-10 follow-up: `nslookup_mx` (section-kv).** New generic
> `section-kv` p58 + a `contains mail exchanger = ` hint. A bare `Header:` line
> (colon, no value) is carried DOWN as the key of each plain line beneath it,
> ordinary `key: value` lines above emit as themselves → one entry-prefixed
> `key | value` table (the reviewer's "each gmail entry should have
> `Non-authoritative answer:` as its key"). Plain `nslookup` untouched (its
> `Name:`/`Address:` under the same banner are their own kv pairs → the bare
> header carries nothing → drops). Auto-detect first cut stole 20 tools; gated
> to 0 (carried members need an INTERNAL tab after indent — excludes rpm -qi
> prose, ipset token lists, perf-list padding, cgget tab-indent — plus ≥1 kv
> before the first section, no kv-pair members, no pre-header loose lines).
> Manifest `nslookup_mx` `table 5 1` → `7 2`. Gate 3452/0/253, 0 deleted;
> extract 62/62, smoke 58/0. **3 open:** kubectl-describe-deployment,
> npm-audit-summary, nst-python-traceback-log — see CHANGELOG.

> **2026-08-03 — round-10 marks (post-merge, fresh branch).** 13 of 17 worst-20
> disagreements fixed. `equals` pin/cfg list modes (pip-freeze, rye-list,
> rustc-cfg — entry-prefixed rows, cfg gated on a bare flag token so env/wpa
> snapshots stay wide); `indented-colon-groups` relative/indented headers + `=`
> split (perl-v); `tsv` leading-tab fix (ldd); new strategies dep-tree,
> arrow-map, numeric-lead-records, brace-groups, checking-groups; powertop
> hint. Free riders: mangohud (bare-flag data-loss fix), pipdeptree full/reverse
> (tree-view). 5 manifest rows retyped to row-shaped output. Gate 3452/0/253,
> 0 deleted (three regen passes each caught + fixed a deletion). **4 open:**
> kubectl-describe-deployment, npm-audit-summary, nslookup_mx (colon-header
> banner variant), nst-python-traceback-log — see CHANGELOG.

> **2026-08-03 — round-9 part 3.** Three new generic strategies close four
> more marks: `repeated-lead-records` p38 (keepalived label|value,
> bluetoothctl label|id|value), `ledger-balance` p44 (hledger amount|account
> + scalar total; also fixed the ledger-balance tool's own garbage golden),
> `banner-groups` p34 (fossil `=== date ===` carried down; nst-ip-route
> improved free). First cut broke 33 tools; documented gates took it to 0.
> Gate 3451/0/254 (2 goldens ADDED, 4 modified — 2 reviewer-directed, 2
> replacing garbage), 0 deleted. **12 of 19 round-9 disagreements now fixed;
> 7 open** — see CHANGELOG for why each remaining one is genuinely hard
> (sdparm colon-gate conflict, btrfs multi-output design, cmb-cr prose-rule
> wall, decode-dimms tab-kv, dvc-dag ASCII DAG, go-ycsb mixed sections,
> hugo-version convention decision).

> **2026-08-03 — round-9 part 2 + engine speed.** Fixed `pre-commit-run`
> (dot-leader form C, colonless), `env-diff` (signed `+KEY=value` in equals),
> `hwinfo-short` (multi-token members in indented-colon-groups, two new
> anti-theft gates), and `fdbcli-status` (` - ` member pairs split to
> `group | key | value`) — see CHANGELOG for the gates and the one
> reviewer-directed manifest change (hwinfo-short `15 1` → `8 2`). Engine:
> `--batch-out` + discovery caches take the full gate ~10 min → 3m51s, and
> `run.sh --golden '^iostat'` re-checks only matching tools. Batch mode also
> got two latent bugs fixed (skipped normalisation pipeline; winner leak).
> Async smoke poll window doubled after a CI shard timed out while its twin
> passed. **Open: 10 round-9 disagreements** — next: `keepalived-vrrp-state`
> (first-token records), `sdparm-all`/`fossil-timeline` (section banners as
> carried-down column), `bluetoothctl-devices`/`hledger-balance` (lost data),
> and 5 marked without notes (`btrfs-filesystem-show`,
> `cmb-cr-redraw-progress-final`, `decode-dimms`, `dvc-dag`, `go-ycsb-run`,
> `hugo-version`).

> **2026-08-03 — round-9 marks, part 1: iostat family fixed.** The reviewer
> marked 26 of the 150-entry round-9 batch (19 disagree, 7 agree —
> `docs/review-marks-2026-08-03-round9.tsv`). The biggest cluster was
> `iostat-{x,cx,xz,xmt}` + `nst-iostat-multisection`, all one root cause:
> `embedded-table` rejected `%`-led header tokens, its detection policy sat
> inside `_et_scan` where the hint path also hit it, and single windows dropped
> repeated sections. Fixed as embedded-table 1.1 + an `avg-cpu:` hint row (5
> matching inputs, all targets). Numeric-aware boundary snap also repaired
> `sfdisk-l`'s welded golden and `nst-vmstat-sections`' separator garbage.
> - Verified: gate 3449/0/256 (4 goldens ADDED, 3 modified-better, 0 deleted),
>   extract 62/62, smoke 58/0, melt 10/0. First-cut lessons are in CHANGELOG
>   (nearest-edge snap broke dotnet/parted until restricted to numerics).
> - **Remaining round-9 work: 14 disagreements**, triaged in CHANGELOG — next
>   easiest: `pre-commit-run` (colonless dot-leader form), `env-diff` (equals
>   with +/- sign prefix), `hwinfo-short` (multi-token members for
>   indented-colon-groups).
> - **Design note from the reviewer:** an input may deserve MULTIPLE outputs —
>   e.g. iostat's avg-cpu kv block AND its Device table are both real data, but
>   the engine's one-winner model keeps exactly one. Today we take the table
>   and drop avg-cpu. Honouring both means a `--max-strategies >1`-style merge
>   or section-splitting ahead of detection — an architectural decision, not a
>   parser tweak; not started.

> **2026-08-03 — round-8 reviewer marks: all ten now answered.** The last three
> disagreements (`perf-bench-sched`, `bowtie2-align-summary`, `hammerdb-tpcc`)
> are fixed. Each was a genuinely distinct shape and needed its own change:
> - **`colons` 1.0 → 1.1** — `#` comment banners no longer count in the 40%
>   key/value detection ratio (either side of it). `perf bench sched` was 25%
>   with its three banner lines, 100% without; the banners were already being
>   dropped at extract time. Now `Total_time | 0.882 [sec]`.
> - **`unspaced-colon-kv` (NEW, p52)** — `Label:value` with no space after the
>   colon, which `colons` (p60) cannot take because that space is what tells a
>   pair from a colon inside a value. Emits records, since labels repeat.
>   `hammerdb-tpcc` → 4 × `label | value`.
> - **`count-percent-label` (NEW, p42)** — `N (P%) text` alignment summaries into
>   `count | percent | label`. `bowtie2-align-summary` → 8 rows × 3 columns.
> - **Verified:** golden gate **3445 passed / 0 failed / 260 ⏳**, extract 62/62,
>   smoke 58/0, melt 10/0. Exactly 3 goldens changed (the intended targets),
>   **0 deleted, 0 added** (rule 5). The first cut of `unspaced-colon-kv` broke
>   25 tools; nine documented gates took that to 3, then 0. `count-percent-label`
>   never caused collateral change.
> - Manifest rows left as `text … 2` for all three: `mincols` is a floor the new
>   output clears, and rewriting the manifest from our own output is what we
>   declined to do for `v4l2-ctl-list-devices`. Goldens are the real gate.
>
> **Still open for a human:** `v4l2-ctl-list-devices` tidies to `group | value`
> (3 rows) but `expected.tsv` declares `table 6 x 2`, so no golden is written —
> reconcile the manifest or accept the blob. And PyPI Trusted Publisher
> registration (account-level, cannot be done from a session).

> **2026-07-30 — round-8 parser work: indented-colon-groups.** Follow-up on the
> 5 "one column that should be several" cases the reviewer flagged. New generic
> strategy `extract/strategies/delimited/indented-colon-groups.sh` (priority 35)
> parses `header:` over indented single-token members into `group | value`, and
> into `name | path | value` when every member-bearing header carries a ` -- `
> split. Wins `cargo-machete`, `cargo-install-list`, `telegraf-plugins-list`,
> `v4l2-ctl-list-devices`.
> - `cargo-install-list` turned out **not** to be a parser gap: a `hints.tsv`
>   row for `cargo tree` was force-routing it to the blob parser. Narrowed that
>   regex with `[^:]`; the 10 other tools it covers are byte-identical.
> - Detection is deliberately narrow (single-token members, no `key: value`
>   pairs, noise only at the very ends) — 22 corpus inputs share the loose
>   shape, only 5 match, and `ethtool-timestamp` self-rejects.
> - **Verified:** golden gate **3441 passed / 3 failed**, and all 3 failures
>   were the intended targets (their old goldens were the `n|A|total_entries`
>   blob) — 0 unexpected regressions across the other 3441. Goldens then
>   regenerated with **0 deletions** (rule 5), and the confirming re-run is
>   **3445 passed / 0 failed / 260 ⏳**. Extract suite 62/62; the 6
>   hint-dependent tools byte-identical.
> - `parted-print` gained a golden incidentally — proven NOT ours (winner is
>   `embedded-table`; byte-identical with our strategy removed). 3444 → 3445
>   goldens, 261 → 260 not-yet-covered.
> - `v4l2-ctl-list-devices` tidies to `group | value` but `expected.tsv`
>   declares `table 6 x 2`, so no golden is written. **Open question for a
>   human:** reconcile the manifest or accept the blob — not self-resolved.
> - Still outstanding from the reviewer's 10: `perf-bench-sched` (comment lines
>   + one kv), `bowtie2-align-summary` (count/percent/text triples),
>   `hammerdb-tpcc` (colon-separated multi-column). Each needs its own shape.

> **2026-07-30 — round-8 reviewer marks worked.** The reviewer marked the first
> ~11 entries of the pre-screen workbook and disagreed with 10 (marks saved in
> `docs/review-marks-2026-07-30-round8.tsv`). Two responses landed:
> - **Parser fix** (`extract/strategies/delimited/dot-leader-kv.sh`): dot leaders
>   that pad the *key* before the colon (`Reader ...........: Yubico`, gpg/hashcat)
>   are now parsed to clean `key | value`, both leader orderings handled, unpadded
>   stragglers kept, and repeated-key record blocks (hashcat `--benchmark`) left to
>   the record parsers. `gpg-card-edit`, `gpg-card-status`, `hashcat-status`,
>   `k6-summary` re-tidied; 3 goldens + 4 review-output snapshots regenerated;
>   golden gate 3441/0, 0 regressions.
> - **Screen hardened** (`tests/corpus/prescreen.py`): new `key-value-delimiter-in-cell`
>   and `lone-delimiter-column` flags. `looks-fine` 2863→2763, `needs-review`
>   466→568. Catches 5 of the 10 disagreements; `--validate` still 94% on the
>   validated set. The other 5 (`perf-bench-sched`, `bowtie2-align-summary`,
>   `cargo-install-list`, `cargo-machete`, `hammerdb-tpcc`) are "one column that
>   should be several" — semantic, beyond a structural screen; each needs its own
>   parser change. **Next:** those 5 shapes are the outstanding parser work.
>
> **Prior context — 2026-07-30 corpus review pre-screen.** Round 8's review workbook
> (`provost_corpus_review_8.docx`, supplied by the reviewer) is **in sync with
> the corpus but entirely unmarked** — 3,706 entries, 258 pre-stamped
> `VALIDATED` (exactly `docs/review-validated-cumulative.txt`), 3,447 blank
> forms, zero ticked boxes. Verified: its tidy blocks match
> `tests/corpus/review-output/` on 3,703 of 3,705 entries (the 2 differences
> are Word empty-cell rendering artifacts, not output drift). So there is no
> round-8 reviewer feedback to action yet.
> - To narrow what the reviewer must actually look at,
>   `tests/corpus/prescreen.py` triages the 3,448 not-yet-validated entries:
>   **2,863 `looks-fine`**, 116 `looks-fine-thin`, 466 `needs-review`, 3
>   `no-output` → `docs/review-prescreen-round8.tsv`.
> - Calibrated with `--validate` against the existing marks: 95% of the 258
>   validated tools pass, 38% of the round-3 `Horrible` tools are flagged.
>   It is a *structural* screen — all 17 `Not quite` tools pass it, and
>   spot-checks found real semantic misses inside `looks-fine` (`k6-summary`
>   keeps its dot-leaders, `pgrep-a` leaves pid unsplit from command). Treat
>   `looks-fine` as "skip unless you want to be thorough", not as a sign-off.
> - A Word workbook of the 2,979 passing entries, ordered most-likely-to-be-
>   wrong first, is reproducible in-repo:
>   ```bash
>   npm install docx
>   python3 tests/corpus/prescreen.py --emit-json /tmp/good.json
>   node tests/corpus/make_review_doc.js /tmp/good.json good.docx
>   ```
>   Verified: XSD-valid, and all 2,979 input blocks and 2,979 output tables
>   round-trip byte-exact against the corpus. (`soffice` cannot open *any*
>   .docx in this container — a trivial one fails too — so it was checked by
>   XSD validation plus text round-trip, not by rendering.)
> - The reviewer's own `.docx` workbook still has no generator in-repo; this
>   covers the pre-screen output only, not the full 3,706-entry form.

> **2026-07-24 — pip-only install + pure-ASCII bundle.**
> - Install is now `pip install provost-data` only; `install.sh` deleted and
>   its references removed from `README.md`, `pyproject.toml` (sdist),
>   `tests/smoke.sh` (symlink-launcher test dropped), `CLAUDE.md`, and
>   `analyze/completions/HANDOFF.md`.
> - `bundle.txt` regenerated with the updated `shared_tools` `merge.sh` so it
>   is straight printable ASCII — no escape characters, no non-printable or
>   non-ASCII bytes. New `FILE-ESC` section (bundle format v3) escapes only
>   offending byte-runs as `<TOKEN><hex><TOKEN>`, where `<TOKEN>` is the
>   shortest tree-absent alphanumeric marker, declared in the header
>   (`# esc-delim:`). Byte-for-byte round-trip verified (11,904 entries,
>   checksums OK). Next: nothing outstanding for the bundle; if the tree
>   changes, rerun `bash ../shared_tools/scripts/merge.sh bundle.txt .`.

> **2026-07-23 — deframe integration fixes.**
> - `provost [inject|run] --plugin-dir DIR` / `PROVOST_PLUGIN_DIR`: forwarded to
>   the engine's `--plugin-dir` so external strategies (deframe) compete in
>   detection without the `~/.mfe/strategies` symlink; validated up front,
>   recorded in `meta.tsv` as `plugin_dir`.
> - `#%` metadata prologue: leading `#%` lines are peeled in `_ingest`
>   before detection (can't corrupt generic parsers), stored as
>   `captures/<id>/context.txt` + `context` meta key; `output.txt` /
>   `provost source` stay verbatim; mid-file `#%` lines are data.
> - Smoke 49 → 59 checks (plugin + prologue coverage). Docs: help, man,
>   completion, README ("Integrating from another tool" + badges).

> **2026-07-23 — pip-installable + PyPI-ready + REUSE.**
> - `pip install provost-data` installs the `provost` command: hatchling wheel
>   bundles the whole Bash tree under `provost_data/_bundle/` (runtime paths
>   only — force-include list in `pyproject.toml`; hatchling `exclude` does
>   NOT apply to force-include, so a new runtime subdir under `extract/` or
>   `analyze/` must be added to that list). Python launcher in
>   `src/provost_data/` execs the bundled script via bash; version is dynamic
>   from `VERSION`. PyPI name `provost-data` (`provost` + `provost-cli` are taken).
> - Tests: `tests/python/test_launcher.py`, 100% line+branch coverage
>   enforced (`--cov-fail-under=100`, wired into pyproject + CI
>   `python-package` job, which also builds, twine-checks, installs the
>   wheel, and pushes a capture through it).
> - REUSE (spec 3.3): `REUSE.toml` bulk-declares GPL-3.0-only,
>   `LICENSES/GPL-3.0-only.txt`; `reuse lint` compliant; `reuse` CI job.
> - Release: `.github/workflows/release.yml` → PyPI Trusted Publishing on
>   GitHub release. **Next step for a human**: register the trusted
>   publisher on pypi.org (project `provost-data`, repo
>   `MartinGallagher-code/glean`, workflow `release.yml`, environment
>   `pypi`) — details in the workflow header — then publish a release.

> **2026-07-19 — R5b list-explode + R7 charts (all rounds now landed).**
> - `lib/_helpers.sh` `_list_explode`: json/yaml with ONE indexed list
>   (`prefix.N[.sub]`) explode to one row per element, scalars repeated —
>   avro `fields`, amtool `Peers`, skopeo `Tags`, docker-manifest, flink,
>   kafka, lscpu, mimirtool, solr, cfssl, rethinkdb, podman (15 flips, all
>   improvements, re-frozen). Contained by a **dominant-list guard** (record
>   lists always; bare-scalar lists only when they out-number the scalar
>   siblings — so config `tags`/npm `maintainers`/opa `required_labels` stay
>   one wide row, honoring R5) and an **empty-prefix guard** (bare `.N` jq
>   array artifacts in kubectl-config/nvim-checkhealth never trigger).
> - `delimited/asciigraph.sh`: line-chart footer (x-axis + `series v v v`)
>   → one row per point, graphics dropped (asciigraph-plot → 6 rows).
> - Honest ⏳ (nothing to recover): asciichart-boxed/series-frame (box-drawn
>   series, only y-scale labels — no per-point data), amdgpu-top (two
>   independent tables, one-dataset-per-input mismatch; a partial parse would
>   drop half the data).
>
> All 7 reviewer rounds (R1–R7) + R5b are now landed. Remaining corpus ⏳
> (261) are format-genuine hard cases, not reviewer asks.

> **2026-07-18 — R6 finished + round-3 specifics + R5b (contained).** Seven
> more contained wins, each gated to zero corpus regressions:
> - `delimited/alias-list.sh` (NEW): `alias NAME='CMD'` → name/command table.
> - `delimited/dot-leader-kv.sh` (NEW): `label: …… value` (artillery) → one
>   key/value row per metric, leaders stripped.
> - `delimited/pipe-cells.sh` (NEW): atop `PRC | sys 1.42s | …` → long
>   group/key/value, pipes removed (6 groups → 28 rows).
> - `delimited/grouped-list.sh` (NEW): asdf version listing → group/value/
>   current long form (version-specific detection so it stays off
>   indented-hierarchy trees / plain lists).
> - `delimited/embedded-table.sh`: admit a positionally-aligned short row
>   (blank interior cell) after a full-width anchor — bundle-outdated 3→5
>   rows; spec-cpu multi-word-label header stays with aligned-columns.
> - `columnar-specs.sh`: apache2ctl-modules → module/type; apk-list (NEW
>   spec) → package/arch/origin/license/status, brackets unwrapped, the
>   space-bearing licence kept whole in one column via absorb.
>
> Goldens re-frozen for the 7 (+manifests text/kv→table where reclassified).
> **Deferred, needing a focused pass / reviewer sign-off** (each is large or
> has no recoverable tidy shape): R5b list-explode convention (amtool Peers,
> avro fields — a JSON/YAML list → one-row-per-element change with
> corpus-wide golden churn), ansible-version header-as-field kv; R7 charts
> (asciichart = pure box-drawing, no tabular data; asciigraph needs a
> fragile chart-axis heuristic; amdgpu-top is two independent tables that
> can't share one tidy dataset). aptitude-search left on its text-lines
> hint (tool-specific fixed-width prefix). Review doc regenerated as
> `provost_corpus_review_7.docx` (258 VALIDATED).

> **2026-07-15 — reviewer round R1 (column fidelity).** The user filled the
> 3,706-page review workbook for the `a*` pages (195 reviewed: 140 OK /
> 31 Not quite / 23 Horrible); ingested marks live in
> docs/review-marks-2026-07-15.tsv and the 7-round fix plan in
> docs/0002-review-fix-plan.md. R1 = the worst cluster: aligned-columns
> splitting multi-word headers/values (akamai silently DROPPED a column).
> Fixes: equal-token-count positional gate (+ data-segmentation match);
> sub-column refinement in `_ac_assign` — a multi-token header window
> splits only when every label edge-aligns ±1 with data in >=60% of rows,
> guarded by eight vetoes each earned from the 89-flip audit (max-tokens>=k
> melt-collision guard, alnum-only witnesses, per-ordinal sparse
> denominators, bridge tokens, duplicate sub-labels, between-value bare
> separators, prose-header stopword veto, lsusb digit-template exemption);
> char-accurate bash grid for narrow-2-byte non-ASCII (asv's ±) with
> ragged label-overlap fallback; colons takes bracketed kv (adb getprop)
> and multi-word colon labels (apt-cache-stats, bazel, rsync-stats →
> wide kv records); inline-kv colon flavor + gauge unwrap (aria2c);
> trailing phrase-merge (aa-unconfined) and scaffold-word split (arp -an).
> All 11 R1 reviewer fixtures match the requested output. 47 goldens
> re-frozen (audit: improvements only; a dozen fixed silently-SHIFTED
> goldens), 6 manifests recalibrated. Gates: golden 3438/0 (0 deletions),
> extract 62/62, smoke 49/0, melt 10/0, analyze 8/8. Coverage headline
> unchanged (fidelity round): **3582 tidy, 124 ⏳**.
>
> **Next:** R2 headerless detection (csv tab-dominant decline, dual-row
> shape test for amixer, ARN colon-split in line-records, at/atq datetime
> cells, anacron constant-prefix). Then R3 chrome ($-prompt/#-comment/
> banner/prose-row strip — also finishes adb-devices' title row and
> arping), R4 hierarchy redesign (indented-hierarchy → kv-under-group
> shape), R5 kv-snapshot wide pivot (convention change, biggest churn),
> R6 decorations, R7 charts. PR #44 (draft) tracks the whole arc.

> **2026-07-14 — kv-under-group (the kv carry-down frontier).** New generic
> `structured/kv-under-group.sh` (p10, outranking key-value at 11): GROUP
> label over indented `key: value` / `KEY value` leaves with the SAME KEYS
> repeating group after group — one wide row per leaf group (`name` +
> per-key columns + nearest outer level as `group`). Closes the shape both
> grouped-rows (table leaves only) and pivot-stats (header/values pivot)
> explicitly could not take: ethtool per-queue stats, nvme per-namespace
> stats (2-level: Controller carried), blkid-style per-device runs.
> Priority 10 demanded the strictest containment yet — the repeated-keys
> signature plus seven vetoes, each from a real gate victim (YAML list/
> anchor markers; `{}` config syntax; multi-word-key mangling evidence;
> within-group key repeats = ifconfig; Titlecase bare keys = geekbench;
> uniform-token bare leaves = lsof table rows; punctuation-only group
> labels = netlify separators). Audit: 17 → 7 → 5 flips, all improvements —
> conan-info (row per package), lshw-memory (dup-key collision recovered),
> nst-btrfs (real stat columns), nst-firewall-zones (a LOST zone recovered),
> nst-rsync (dir names). 4 manifests re-calibrated to the wide convention.
> Gates: golden 0 failed, extract 62/62, smoke 49/0, melt 10/0. **Now 3582
> tidy, 124 ⏳** (✅ 3355 / ✅ʰ 83 / ✅ᵇ 144).

> **2026-07-14 — embedded-table (report shape, nst-* round).** New generic
> `delimited/embedded-table.sh` (p37): prose/kv preamble + ONE dominant
> aligned table + footnotes (smartctl -a, benchmark write-ups, backup/db
> reports, trivy scans). Largest table window, positional slicing with
> midpoint boundaries + overflow snap (`zstd-19`, `Reallocated_Sector_Ct`
> stay whole). Containment (five gate rounds, 31→11→17→5 flips): chrome must
> hold a digit-free PROSE line (all-kv reports like mdadm --detail /
> kubectl describe stay with kv parsers — their fields would be LOST);
> header-identical or token-subset chrome = multi-section table → decline
> (faillock, ps/top reprints, yugabyte); window must open/close a section
> (blank/narrower neighbors, `===` banners excepted) so truncated windows
> inside bigger tables decline (prlimit); `+use` diff lines aren't headers;
> sentence rows aren't data. Closes 5 nst-* report gaps + 9 bonuses
> (cargo-audit, dotnet-list-package, kubectl-get-all, nmap_sv, rocm-smi,
> sfdisk-l, cmb-spinner ×3); upgrades trivy ×4 + nodetool-netstats (5
> manifests re-calibrated — they'd been tuned to command-line-shred mush).
> nst-mdadm-detail-devices stays ⏳ (all-kv chrome; needs kv+table dual
> emission). Gates: golden 3435/0, extract 62/62, smoke 49/0, melt 10/0.
> **Now 3579 tidy, 127 ⏳** (✅ 3352 / ✅ʰ 83 / ✅ᵇ 144 — 5 bespoke-only
> inputs went generic).

> **2026-07-14 — encoding round (enc-* cluster, 6 of 8 + fullwidth-colon
> follow-up).** Engine: VT is context-sensitive (a space inside real-\n input,
> a line break only in \n-less captures); BEL/BS stripped (after the ANSI
> strip — BEL terminates OSC); ZWSP deleted (ZWNJ/ZWJ stay — Farsi half-space,
> emoji joins are content); fullwidth digits + colon → ASCII (closes the
> uni-kv-fullwidth follow-up noted since the Unicode-spaces round).
> aligned-columns: lowercase wordy headers promote when EVERY data row carries
> a token the header lacks — Titlecase or fully non-ASCII (`username fullname
> active` over `alice  Alice Anders  yes`; emoji/Farsi tables) — while
> lowercase name grids (sqlite .tables) stay data. Closes enc-control-mix,
> -vtab-in-cell, -fullwidth-digits, -zwsp-header, -zwj-emoji, -zwnj-farsi;
> deliberately ⏳: enc-formfeed-report (page banners modulo page number),
> enc-two-space-in-value (in-value 2-space run ≡ column gap, undecidable).
> Audit: 11 flips, all invisible-byte / fullwidth normalization improvements.
> Gates: golden 0 failed, extract 62/62, smoke 49/0, melt 10/0. **Now 3570
> tidy, 136 ⏳** (✅ 3338 / ✅ʰ 83 / ✅ᵇ 149).

> **2026-07-14 — spanning group headers + sysstat headers + wrapped rows.**
> Four `aligned-columns` capabilities: HDR2 accepts digit-bearing FIELD rows
> (`p50`, `BW(MB/s)`) — the discriminator is value-shaped tokens, gated on
> alphanumeric row-1 tokens (kills `====` banners) and no lone-punct row-2
> tokens (kills ` X : Y ` kv lines); duplicate header names under group labels
> get the positionally-nearest group as a prefix (`CPU_Req`, `Read_IOPS`,
> `reads_merged`) — before this the melt silently DROPPED the earlier group's
> columns (three-groups/vmstat-d/proc-net-dev goldens all had lost a whole
> group; all three re-frozen recovered); sysstat interval headers
> (`07:00:01  CPU  %user …`) promote despite the leading time, and their exact
> mid-table repeats drop when rare (<=1/4 of rows); a lone-token row + indented
> one-short row merge as a wrapped column-1 value (df device paths). Closes 5
> tbl-* targets + sar-cpu + quota-report (both long-documented hard-tail gaps).
> Audit: 8 first-cut flips → 5 contained → final 3, all improvements. Gates:
> golden 0 failed, extract 62/62, smoke 49/0, melt 10/0. **Now 3564 tidy,
> 142 ⏳** (✅ 3332 / ✅ʰ 83 / ✅ᵇ 149).

> **2026-07-14 — quoted-delimiter round (quo-* cluster, 8 gaps + 1 bonus).**
> Five format-level capabilities: `psql-table` honors `\|` escapes in cells;
> `pipe-table` gains a strictly-gated BARE dialect (`a | b | c`, no outer pipes,
> no rule; escape+quote-aware split; no cell may hold a 2+-space run so TUI
> gauges never match; digit-leading row-1 cell ⇒ headerless) — closes 2 quo
> gaps + `git-log-pretty-pipe` and upgrades 7 fixtures from literal-`|` mush to
> real columns; `inline-kv` tokenizes quote-aware (logfmt `msg="…"`) and keeps
> a leading `label:` as a `name` column (blkid keeps its device); `tsv` splits
> quote-aware (`"a<TAB>b"` one cell, tab runs still collapse) + numbered-series
> header rescue (`col1 col2 col3`); new `delimited/two-col-gap.sh` (p54) for
> the long-documented "2-col table, free-text last column" class, contained by
> value-no-2+-space-run, data-row spacey evidence, modal-word-count grid
> decline (>=2/3), header-matches-modal decline, digit-leading headerless.
> Containment was hard-won: first cut fired on ~600 inputs; three audit rounds
> (670→45→31→17→16 flips) ended at 16 improvement re-freezes + 9 new goldens,
> 0 regressions, 0 deletions. One manifest fix (`mimirtool-rules-list` 5→4,
> was calibrated to the old junk `|` column). Gates: golden 3408/0, extract
> 62/62, smoke 49/0, melt 10/0. **Now 3557 tidy, 149 ⏳** (✅ 3325 / ✅ʰ 83 /
> ✅ᵇ 149).

> **2026-07-13 — wide fixed-width follow-up.** Two generic fixes for wide tables
> that were dropping columns. (1) `columnar-specs` `_cs_row_overflow`: a
> fixed-layout ws spec (no absorb, no `@rest`) declines when ≥80% of its data
> rows carry MORE tokens than it has columns — it was silently dropping the
> extras and mis-labelling the rest (`turbostat`'s 10-col spec mangling the
> 20-col `turbostat -q`); also de-false-positives `hadolint-output` (the
> `dpkg-get-selections` spec grabbed it for ending in "…install"). (2) `tsv`
> header rescue: row 1 was treated headerless whenever a field merely CONTAINED
> a digit, demoting real headers with digit-bearing labels (`Core CPU … C1 C6`);
> now a dual-row check keeps row 1 as a header when a column is a label in row 1
> over a numeric value in row 2, gated ≥3 columns so 2-col KV/pair lists (`wg
> show`, colon-KV) stay headerless. Closes `turbostat-wide` + `enc-tsv-numeric`
> (⏳→✅), real column names for nvidia-topo + featurecounts. Blast radius audited
> 50→5→final; 0 regressions. **Now 3548 tidy, 158 ⏳** (✅ 3316 / ✅ʰ 83 / ✅ᵇ 149).

> **2026-07-13 — manifest-discipline follow-up.** Completes the strict-`_ok`
> pass (text-kind now honors the manifest's `emin`, not a hardcoded ≥2). Two
> parser fixes surfaced by the strict re-run: `yaml.sh` no longer false-claims
> `/proc/interrupts` numeric tables (a `key` must start with a LETTER, so `0:`/
> `16:` IRQ ids don't count as YAML keys) — 143→140 yaml winners, 3 clean
> declines (proc-interrupts-smp→aligned-columns, docker-pull-layers +
> ogrinfo-layers→labeled-records, all ✅); `iostat-x.sh` detect keys on `aqu-sz`
> alone so the reduced-column `iostat -c -x` (`iostat-cx`) is tidied bespokely
> (✅ᵇ) instead of losing its Device table to block-records. Re-ran
> `--update-golden` under strict `_ok`: 33 stale-loose generic goldens deleted
> (all triaged as genuine shortfalls, not miscalibration — the bespoke-covered
> subset moves ✅→✅ᵇ, the rest become honest ⏳); one real miscalibration fixed
> (`apt-get-download-progress` mincols 4→2, was tuned to pre-bugfix garbled csv).
> Gates: golden 3397/0, extract 62/62, smoke 49/0, melt 10/0. **Now 3546 tidy,
> 160 ⏳** (✅ 3314 / ✅ʰ 83 / ✅ᵇ 149) — the honest number after the discipline
> pass stops ~28 lossy parses counting as tidy. Frontier (documented, not fixed):
> wide fixed-width tables dropping columns generically (turbostat-wide 12/20,
> storcli-show, nvidia-smi-full, sar/iostat generic paths).

> **2026-07-13 — aligned-columns kv-header guard + csv thousands-comma false
> positive.** From a manual review of `tests/corpus/review-output/`: (1)
> `aligned-columns` was claiming single-record colon-kv description blocks
> (`apt-cache show`, `dpkg -s`) before `colons` could, hijacking row 1's two
> tokens as column names — `_ac_shape` now declines when the block is
> majority-distinct `Label:` lines AND row 1 itself is one (the second check
> spares real tables like `/proc/interrupts` whose first *column* is
> colon-suffixed labels but whose row 1 is a real header). Fixes
> apt-cache-show-vim/curl, dpkg-s-nginx, dpkg-status-openssl,
> ipset-list(-hash), helm-status. (2) `csv` was false-positive-detecting on
> `apt-get` download-progress lines because bracketed thousands-grouping
> commas (`[1,234 kB]`) gave a spuriously consistent per-line comma count; new
> `_csv_strip_thousands` excludes a comma from the count only when it's a true
> grouping comma (digit before, exactly 3 digits after, no 4th) — precise
> enough to leave real separator commas alone (`eu-west-1,881204`) and to NOT
> erase the bracket-internal comma-count variation `vegeta-report` needs to
> correctly decline csv. Fixes apt-get-download-progress + vegeta-report,
> un-breaks 8 incidental pre-existing false-positive csv winners, and closes
> the `perf-stat-scientific` ⏳ gap. `ledger-balance` now correctly declines
> csv too; its next-best winner (`vertical-line`) is imperfect but matches the
> already-accepted lossy pattern on `hledger-balance` (both loose `text` kind
> — flagged for the pending manifest-tightening pass, not fixed here). Golden
> gate 3430 passed / 0 failed / 276 not-yet-covered (pre-existing gap, no
> golden ever frozen for those — unrelated); extract 62/62; smoke 49/0; melt
> 10/0. 9 goldens re-frozen, 1 new (perf-stat-scientific). Full-mode
> `--coverage` regen: **3571 / 3706** (✅ 3346 / ✅ʰ 84 / ✅ᵇ 141). The
> committed `COVERAGE.md` had drifted stale (last regenerated before the
> grouped-rows/pivot-stats rounds landed, still showing 3478/3706) — this
> commit both catches that up and folds in this round's fixes, net +93 items
> tidy, -1 (`lsusb-v`, confirmed via an `e4acc0b` worktree comparison to be an
> unrelated pre-existing gap the stale doc just hadn't surfaced, not a
> regression from this change). Next queued: Bug
> #1 — tighten the loose `text`/`kv` manifest kinds in `expected.tsv` (a
> corpus-discipline pass, not a parser fix) now that 2 and 3 are done.

> **2026-07-13 — pivot-stats (ip -s link pivot).** New generic
> `structured/pivot-stats.sh` (priority 39): label line names counters, NEXT
> line carries the values — one wide row per record (name + header `word value`
> pairs + rx_/tx_-prefixed counters). One hint row (`RX: +bytes` → pivot-stats)
> routes the family, incl. past key-value (prio 11) for `ip -s addr`. Closes 4
> fixtures + improves exo-ip-s-s-link (old golden was welded blobs). Residuals:
> `ip -s -s` doubled stats (2-token `RX errors:` label) drop error details;
> nvme/ethtool kv-under-group stay ⏳ (key-value steals at prio 11, different
> shape). **Now 3571 tidy, 135 ⏳** (✅ 3347 / ✅ʰ 82 / ✅ᵇ 142).

> **2026-07-13 — grouped-rows (nested-records frontier).** New generic
> `structured/grouped-rows.sh` (priority 41): GROUP line (Label:/KEY=val/
> trailing-colon/bare-token/inline-pairs) over indented tabular leaves, 2
> levels, group keys carried onto each row. Containment: leaves must be a
> table (modal tokens ±1 ≥70%, leaves ≥ groups), YAML list markers abort,
> priority sits after block-records/tree-view; 4 kv-flavoured victims pinned
> back via hint rows (volta, vulkaninfo, numpy-config, lsusb-verbose).
> Closed 11 nested ⏳; PROMOTED iotop + proc-devices ✅ᵇ→✅; improved pulumi/
> yugabyte (carried group column). ip -s link stays ⏳ (label line = header
> for the NEXT row — a pivot, different shape). README headline corrected to
> tally-derived numbers. **Now 3567 tidy, 139 ⏳** (✅ 3348 / ✅ʰ 77 / ✅ᵇ 142).

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

`provost` is the single-binary tool proposed in
[docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md)
to replace the three-binary `envoy-*` suite. It lives in its own repository and
is **fully self-contained**: the entry point resolves its engines from its own
directory (`PROVOST_ROOT`), so it runs with no external dependencies.

> **2026-07-06 — cut from Envoy.** The `extract/`, `analyze/`, `transform/`, and
> `lib/` trees are first-party provost code, maintained in this repo directly.
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
   `help_overlay` tests (surfaces provost doesn't ship — the raw
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
free -m        | ./provost            # captures in the BACKGROUND by default (async)
free -m        | ./provost --sync     # foreground: prints the resulting dataset + #N
docker stats   | ./provost
./provost run df -h                   # capture a command's output AS A COMMIT
./provost ls                          # list datasets
./provost show free                   # present a dataset as a tidy table
./provost stats free                  # statistics via the analyze engine
./provost source 5                    # the original input behind row #5
./provost triage                      # low-confidence / unmatched bucket (raw input decoded)
./provost show unsorted               # same bucket as a table; base64 raw decoded to text
./provost rm free                     # delete a dataset + its captures (purge is default)
./provost rm -f --no-purge free       # delete the dataset but keep the source captures
./provost doctor                      # engine + store check
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
The store is a **git repo** (`$PROVOST_WORKSPACE`). Every capture is one commit,
tagged `capture-<id>`; each writes `captures/<id>/{meta.tsv,output.txt}` alongside
the dataset change. `provost log` lists captures; `provost restore <id|latest>` brings
one back up. This is a simplified linear-history model (proposal 0001 §7).

### Store model
- **Global by default** — `$PROVOST_HOME` or `~/.provost`; capture from anywhere.
  `PROVOST_WORKSPACE` explicit override wins (tests use it).
- **Per-row provenance** — every dataset row has a globally-unique visible `#N`
  index; `provost source <#N>` returns the exact captured input that produced it.
- **Multi-user** — `mkdir` store lock + double-checked `git init`; verified under
  8-way concurrency.
- **Controlled dirs** — `provost control [<dir>]` makes `<dir>` its own instance;
  resolution walks up from CWD (override → controlled → global).
- **Export / import** — `provost export` writes a portable `git bundle`;
  `provost import` reconstitutes it elsewhere with provenance intact.

### Analyze (`analyze/`)
`provost stats <dataset> [args]` runs the analyze engine over a dataset's TSV.
The `browse`/`dashboard`/`pipeline` surfaces are intentionally absent, and
their orphaned tests were deleted — the raw analyze suite runs green.

### Schema reconciliation
`_store_append` unions a differing-column same-type capture into the base dataset
when column overlap ≥ `PROVOST_RECONCILE_OVERLAP` (default 60%), blank-filling both
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
   `provost`-native names (large, internals-only).

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

fio is now fully handled: of its 12 output modes provost tidies 9 (json, bw-log,
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

`smoke.sh` is hermetic — it clears the caller's `PROVOST_*` env (notably
`PROVOST_HOME`) so a stale `~/.provost/extract` engine can't shadow the bundled one
and skew classification. If a real `provost` run misclassifies, check
`provost doctor`: it warns when the extract engine came from a `PROVOST_HOME`
override rather than the bundled tree.
