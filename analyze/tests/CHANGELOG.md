# Changelog — EnvoyAnalyze/tests

## 2026-06-15 — browse title help smoke
- Extended the dashboard alias smoke test to assert that `envoy-browse --help` documents the new `--title` dashboard context option. Files: `test_dashboard_alias.sh`, `HANDOFF.md`.

## 2026-06-15 — dashboard alias smoke test
- Added a smoke test for `envoy-dashboard --help` so the watch alias remains wired. Files: `test_dashboard_alias.sh`, `HANDOFF.md`.


## 2026-05-20 — version bump 1.0.0 → 1.1.0
- `test_mda.sh::test_version_string`: bumped the assertion from
  `v1.0.0` to `v1.1.0` to track the parallel `VERSION` bump in
  `envoy-analyze`. Without this the test failed once the tool's
  `--version` banner matched the canonical suite version.
- Files: `test_mda.sh`.

## 2026-03-31 (--top-n tests)
- **Added**: `test_top_n.sh` — 8 tests for the `--top-n N` flag: count limits (3, 1, 0), error handling (missing value, non-numeric), large N passthrough, --good filter interaction, JSON format compatibility.

## 2026-03-05 (Update test files for executable renames)

- **Updated**: `helpers.sh` — updated `MDA_SCRIPT` path from `mda.sh` to `envoy-analyze`; updated comments.
- **Updated**: `test_mdx.sh` — updated `MDX_SCRIPT` path from `mdx` to `envoy-browse`; updated comments, assertion messages, and test descriptions.
- **Updated**: `test_performance.sh` — updated comments referencing `mda.sh` to `envoy-analyze`.
- **Updated**: `test_csv_parsing.sh` — updated comments referencing `mda.sh` to `envoy-analyze`.
- **Updated**: `test_correctness.sh` — updated assertion messages and comments referencing `mda` to `envoy-analyze`.
- **Updated**: `HANDOFF.md` — updated references to new executable names.
