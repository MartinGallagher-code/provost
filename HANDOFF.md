# Handoff — provost

The history that used to live here (2026-07 → 2026-09-16, ~100 KB) is in git:
`git show 9f9d7c0:HANDOFF.md`. `CHANGELOG.md` has the dated detail.

## Present state (2026-09-25)

provost 2.0.1 — one Bash entry point (`provost`) over the extract engine (257
strategies, `extract/`), the tidy melt (`transform/melt.sh`) and the analyze
engine (`analyze/`), with a git-backed store. Shipped on PyPI as a thin Python
launcher (`src/provost_data/`).

A full assessment on 2026-09-25 found and fixed: silent data loss on captures
over ~3,000 rows, capture-id reuse that corrupted provenance, path traversal
and command injection in the CLI, code execution via a shared store or a
`.envoyrc`, value corruption (spaces → `_`, TSV empty cells, digit-suffixed
names), and detection that was 10× slower than it needed to be. See the
2026-09-25 CHANGELOG entry.

Behaviour worth knowing:

- `provost run CMD` names the dataset after the command; piped input is named
  after the winning parser; `--name` overrides.
- Background capture only at an interactive terminal; scripts are synchronous.
  Failures: `provost log --failed`.
- Captures/`rm` are refused while `provost restore <id>` has a capture out.
- A store whose `.git/config` others can write is refused if it sets keys that
  make git run programs.
- Engines run with `ENVOY_NO_RC=1`; the `.envoyrc` layer is off under provost.

Suites (all CI-enforced): `tests/smoke.sh` (197), `transform/tests/test_melt.sh`
(42), `extract/tests/run_tests.sh` (~2 min), `analyze/tests/run_tests.sh`
(mawk and gawk), `tests/corpus/run.sh --golden`, `python -m pytest`.

## Next steps

1. **Decide on two repo-weight items** (deletions were held for the owner):
   `bundle.txt` (9.5 MB, a whole-tree copy committed on every change — could be
   built on demand or attached to releases instead, dropping
   `tests/check-bundle-current.sh`), and `tests/corpus/review-output/` (15 MB,
   94% byte-identical to `expected/`; `tests/corpus/review-snapshot.sh` now
   regenerates it, so it can be gitignored).
2. **Large inputs are still slow**: a 10 MB table takes ~4.7 min, all in bash
   detection (~245 detectors × the full text). Next lever: detect on a bounded
   head/tail sample, or engine-level required-token headers — only with a
   corpus run proving winners don't change.
3. **Confidence doesn't rank candidates** (priority does). Ranking by
   confidence would flip 43% of corpus winners because `line-records` always
   reports 80; calibrating strategy confidences is the prerequisite.
4. Old stores keep a `total_entries` column in existing datasets; new rows
   blank-fill it. A one-off migration could drop it if that matters.
5. The `envoy-*` / `ENVOY_*` / `MFE_*` internal names remain (a large rename,
   deliberately separate).
