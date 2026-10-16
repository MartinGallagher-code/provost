# Handoff — provost

The history that used to live here (2026-07 → 2026-09-16, ~100 KB) is in git:
`git show 9f9d7c0:HANDOFF.md`. `CHANGELOG.md` has the dated detail.

## Present state (2026-10-14)

**provost 2.1.0 is prepared** (`VERSION`, man page header, and a CHANGELOG
release entry). PyPI still serves 2.0.1 until a GitHub release tagged
`v2.1.0` is published on the merged commit; `release.yml` then uploads it.
2.1.0 is the first release that ships the rename (`provost-extract` /
`PROVOST_*`), store format 2, line coverage and the 2026-10 parser work.

provost is one Bash entry point (`provost`) over:
- the extract engine (`extract/provost-extract`, 264 strategies, ~115 of them
  generic)
- the tidy melt (`transform/melt.sh`)
- the analyze engine (`analyze/provost-analyze`)

It has a git-backed store and ships as a thin Python launcher
(`src/provost_data/`).

### This round (2026-10-14)

- **Whitespace tables: cells by column offset.** The "gutter grid" in
  `extract/lib/_helpers.sh` is used by aligned-columns, fixed-width and
  embedded-table. It also handles:
  - banner, title and footer lines
  - IIS `#Fields:`
  - preamble `Label: value` lines, kept as constant columns
  - headerless tables
- **Diagnostics, logs and help text.**
  - `prefix-message` splits typed prefix fields followed by a message, and
    attaches continuation lines to the record above.
  - `help-columns` splits a term from its description.
- **Line coverage.**
  - Every parse now reports the share of input lines it used: in
    `--emit-meta` (4th field), in `--explain`, and in provost's ok line and
    `meta.tsv`.
  - A single-winner claim under 60% is held, and the rescue-only `kv-report`
    replaces it when it covers at least 25 points more.
  - `gnu-version` now keeps the whole report.
- **Round-2 benchmark re-rated:**

  | | before | after |
  |---|---:|---:|
  | PASS | 16% | 24% |
  | PARTIAL | 47% | 50% |
  | FAIL | 38% | 27% |
  | usable | 62% | 73% |

  No input regressed. **This set has been looked at now, so it is a
  regression measure, not a generalisation one.**
- **Corpus:** 3579 golden passes, 0 failed (was 3557). COVERAGE.md shows
  3675 / 3705 tidy.

The engines honour the pre-rename `ENVOY_*` / `MFE_*` names and
`~/.mfe/strategies` for one release. Remove that "Legacy names" block, and
the legacy dir in `_collect_strategy_dirs`, in 2.2.0 (the release after 2.1.0,
which first ships the rename). `tests/corpus/*/envoy-*` are real Envoy-proxy captures.

Behaviour worth knowing:

- `provost run CMD` names the dataset after the command. Piped input is named
  after the winning parser. `--name` overrides both.
- Capture runs in the background only at an interactive terminal; scripts run
  synchronously. Failures: `provost log --failed`.
- Captures and `rm` are refused while `provost restore <id>` has a capture out.
- A store whose `.git/config` others can write is refused if it sets keys that
  make git run programs.
- Engines run with `PROVOST_NO_RC=1`.
- Detection: the best confidence wins, with exact ceiling pruning, then the
  coverage hold. `--rank priority` gives the old first-match order; the rescue
  does not run there.
- Large inputs: above 32 KB, detectors screen a sample and the winner is
  re-confirmed on the full text. The sample is head + tail plus middle
  windows. Coverage is measured up to 128 KB (`_FR_COV_BYTES`).

Suites (all CI-enforced):
- `tests/smoke.sh` (208)
- `transform/tests/test_melt.sh` (54)
- `extract/tests/run_tests.sh` (69 files)
- `analyze/tests/run_tests.sh` (mawk and gawk)
- `tests/corpus/run.sh --golden`
- `python -m pytest`

`tests/corpus/run.sh --coverage` now takes about 11 minutes.

## Next steps

1. **Publish 2.1.0.** Publish a GitHub release tagged `v2.1.0` on the merge
   commit, then check that `pip install provost==2.1.0` works. In the release
   after that (2.2.0), remove the legacy-name fallbacks (see above).
2. **Round 3: a fresh held-out set.** This is the only honest way to know how
   much this round generalised. Gather it the way round 2 was gathered
   (`tests/benchmark/round2/CRITERIA.md`, `novelty.py`), and rate it before
   anyone tunes on it.
3. **What still fails, by pattern** (the round-2 postscript has details):
   - Whitespace tables with non-ASCII cells: the grid withdraws (winget).
     Also gzip -lv, Get-Volume, diff -y.
   - Footers: sqlcmd and SQL*Plus footers are still data rows outside
     aligned-columns.
   - Sections glued into cells: vim, diskutil, route print, ffmpeg. Coverage
     cannot see this; it needs segmentation.
   - The first data row still becomes the header in gcc and dis. Banners
     defeat readelf, pprof and the mainframe report.
   - Suffix grammars such as `unittest -v`'s `... ok`, and curl -v.
   - Patterns 5 (wrong strategy or delimiter: composer claimed by toml at 2%
     coverage, because toml is exempt from the hold) and 6 (meaningful
     indentation) were not worked.
4. **Coverage as a quality signal.** It catches dropped lines, but not values
   under the wrong header: 19 of the 29 round-2 FAILs cover 95% or more. A
   second check, such as column-type consistency, would catch those.
5. 30 corpus tools are still not tidy (`tests/corpus/COVERAGE.md`).
