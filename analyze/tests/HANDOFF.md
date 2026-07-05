# Handoff — EnvoyAnalyze/tests

- 2026-06-15: Extended dashboard alias smoke coverage to assert `envoy-browse --help` documents `--title`.
- 2026-06-15: Added `test_dashboard_alias.sh` smoke coverage for the new dashboard alias.
## Overview

Test suite for EnvoyAnalyze (envoy-analyze + envoy-browse). Uses a shared bash test harness (`helpers.sh`) with `run_test`, `assert_contains`, `assert_not_contains`, `assert_exit_zero`, and `print_summary`.

## Structure

- `helpers.sh` — shared harness, defines `run_mda()`, color output, counters
- `test_mda.sh` — 31 tests for envoy-analyze (correlations, filters, shape, matrix alignment, version, CV, normality, precision, Benford, trend, regression, quality score, PCA, monotonicity, suggested drops, formats, profiles, delimiter, stdin)
- `test_mdx.sh` — 18 tests for envoy-browse (help output, key docs, no-input rejection, bad-flag, --all, --debug, TUI edge cases, unit tests)
- `test_correctness.sh` — 81 known-answer tests across 8 datasets
- `test_csv_parsing.sh` — 11 CSV preprocessing tests (BOM, quoting, embedded newlines)
- `test_performance.sh` — 3 performance regression tests (1K/5K rows, wide datasets)
- `test_diverse_data.sh` — 17 tests (negative numbers, scientific notation, missing values, large datasets)
- `run_tests.sh` — runner, executes all `test_*.sh` files with `bash` explicitly

## Running

```bash
bash run_tests.sh          # run all tests
bash test_mda.sh           # run envoy-analyze tests only
bash test_mdx.sh           # run envoy-browse tests only
```

## Notes

- Test files must have execute permission (`chmod +x`) to be picked up by `run_tests.sh`
- envoy-browse tests are limited to non-interactive checks (help, exit codes) since the TUI requires a TTY
