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

Suites (all CI-enforced): `tests/smoke.sh` (203), `transform/tests/test_melt.sh`
(54), `extract/tests/run_tests.sh` (~2 min), `analyze/tests/run_tests.sh`
(mawk and gawk), `tests/corpus/run.sh --golden`, `python -m pytest`.

## Next steps

1. **Repo weight** (2026-10-01): `bundle.txt` and the committed corpus
   review snapshot are gone (build/regenerate on demand; both gitignored).
2. **Large inputs** (2026-09-25): detection screens a bounded sample above
   32 KB and re-confirms the winner on the full text; the hot generic parsers
   and the engine's own passes have byte-identical awk twins; a big result
   stays in a file to the end; provost melts that file directly. 10 MB now
   takes 7–22 s end to end (was minutes); JSON/XML documents are sampled for
   ordinary detectors while the document grammars see them whole. Knobs `_FR_SAMPLE_BYTES`,
   `_FR_BIG_BYTES`, `_FR_LANE_BYTES` (0 forces a route, -1 disables);
   `extract/tests/test_big_input_paths.sh` compares routes. Share-threshold
   detectors get `_FR_SAMPLE_SLACK` (15 points) while screening the sample,
   so sampled-vs-full winner flips on 360 synthetic big inputs are 0
   (2026-10-01). Remaining risk: evidence that lies only in the MIDDLE of a
   huge input (39 corpus inputs flip under a forced 8+4-line sample).
   colons and block-records have awk twins; 10 MB ps/CSV CPU fell 33%/24%. A strategy whose extract is still a bash line
   loop is slow on big inputs — give it an awk twin, proven over the corpus
   with `_FR_BIG_BYTES=0`.
3. **Confidence ranks candidates** (2026-09-25): confidences follow the
   rubric in `extract/README.md`; every detector runs and the best confidence
   wins (ties: priority, name), with exact ceiling pruning so a strong early
   candidate skips the detectors that cannot beat it. `--rank priority` keeps
   the old first-match order. Bespoke strategies are tiered by signature
   strength (95/92/88/<=80, 2026-10-01; twelve weak detectors tightened).
   `--explain` lists matches in rank order. Open: pnpm-audit (a key/value
   box with a title row) lost to box-table; clickhouse-describe-table and
   clickhouse-system-mutations need box-table to stop promoting the first
   data row; 59 corpus tools are still not tidy (tests/corpus/COVERAGE.md;
   `_tech_kv_colon` dropping `http(s)://` values blocks brew/flatpak info).
4. Old stores migrate to store format 2 on their next write (`total_entries`
   column dropped from datasets).
5. The `envoy-*` / `ENVOY_*` / `MFE_*` internal names remain (a large rename,
   deliberately separate).
