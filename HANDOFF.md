# Handoff — provost

The history that used to live here (2026-07 → 2026-09-16, ~100 KB) is in git:
`git show 9f9d7c0:HANDOFF.md`. `CHANGELOG.md` has the dated detail.

## Present state (2026-10-02)

provost 2.0.1 is on PyPI. It is one Bash entry point (`provost`) over:
- the extract engine (`extract/provost-extract`, ~260 strategies)
- the tidy melt (`transform/melt.sh`)
- the analyze engine (`analyze/provost-analyze`)

It has a git-backed store and ships as a thin Python launcher
(`src/provost_data/`).

The internal names inherited from Envoy (`envoy-*`, `ENVOY_*`, `MFE_*`) were
renamed to provost names on 2026-10-02 (see the CHANGELOG entry). The engines
honour the old variables for one release. **Drop that "Legacy names" block,
and the `~/.mfe/strategies` read in `_collect_strategy_dirs`, in the release
after next.** `tests/corpus/*/envoy-*` are real Envoy-proxy captures, not
leftovers.

Behaviour worth knowing:

- `provost run CMD` names the dataset after the command. Piped input is named
  after the winning parser. `--name` overrides both.
- Capture runs in the background only at an interactive terminal; scripts run
  synchronously. Failures: `provost log --failed`.
- Captures and `rm` are refused while `provost restore <id>` has a capture out.
- A store whose `.git/config` others can write is refused if it sets keys that
  make git run programs.
- Engines run with `PROVOST_NO_RC=1`, so the `.provostrc` layer is off under
  provost.
- Detection: the best confidence wins, with exact ceiling pruning.
  `--rank priority` gives the old first-match order. The rubric is in
  `extract/README.md`.
- Large inputs: above 32 KB, detectors screen a sample and the winner is
  re-confirmed on the full text. The sample is head 120 + tail 40 lines, plus
  middle windows (4 evenly spaced, and up to 4 where a new line shape first
  appears). 10 MB takes 7–22 s end to end.
- Old stores migrate to store format 2 on their next write.

Suites (all CI-enforced):
- `tests/smoke.sh` (203)
- `transform/tests/test_melt.sh` (54)
- `extract/tests/run_tests.sh` (~2 min)
- `analyze/tests/run_tests.sh` (mawk and gawk)
- `tests/corpus/run.sh --golden` (3557 pass, 148 not yet covered, of 3705)
- `python -m pytest`

## Next steps

1. **Generalisation is the real gap.** Benchmark round 2 used 109 unseen
   inputs and was never tuned on (`docs/benchmark-2026-10-02-generalisation-round2.md`).
   It scored 16% PASS, 47% PARTIAL and 38% FAIL, while corpus coverage is
   96.7%. The top failure patterns, in order:
   - column boundaries are taken from whitespace instead of header offsets
   - multi-section reports keep only one section
   - a banner or title line is promoted to the header
   - line diagnostics fall back to a single column

   Fix those in the generic parsers, not with bespoke strategies. Then measure
   on a **new** held-out round 3. Round 2 has been looked at now; don't reuse
   it as the score.
2. Corpus: 31 corpus tools are still not tidy (`tests/corpus/COVERAGE.md` was
   not regenerated: the full `--coverage` run exceeds an hour on a loaded box).
3. Sampling: evidence whose lines share their shape with the head, and that
   no even window lands on, can still be missed. Keep such evidence a
   fallback route in detectors.
4. Strategies whose extract is still a bash line loop are slow on big
   inputs. Give them awk twins, proven over the corpus with `_FR_BIG_BYTES=0`.
