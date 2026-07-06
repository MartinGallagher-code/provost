# lib/awk/ — Standalone awk programs

Introduced by [ENV-123](../../../tickets/archive/ENV-123.md) (2026-04-24). Holds awk programs that are too large or stylistically too rich to live as inline heredocs inside `lib/_*.sh`.

## Why a separate directory

Inline awk heredocs in bash have well-known maintenance issues: editor syntax highlighters treat the body as a string, `awk -W lint` cannot run on an embedded program, and parse errors cite an offset *inside the heredoc* rather than the source line. Splitting the program into its own `.awk` file fixes all three with no build-system overhead — bash invokes it via `awk -f`.

The trade-off (one extra path lookup per invocation) is negligible: each program is invoked once per column, not once per row.

## Contents

| File | Caller | Purpose |
|------|--------|---------|
| `numeric_combined.awk` | `lib/_numeric.sh::_numeric_combined_awk` | Single-pass per-column numeric analysis: histogram, sparkline, mode, precision, Benford's Law, monotonicity, bimodality, z-score outliers, Spearman trend. Emits 9 fixed-order lines parsed by `run_numeric_analyses`. |

## Contract

Every `*.awk` here:

1. **Receives all dynamic values via `-v`.** No bash interpolation in the program body. The header comment lists each `-v` parameter (`col`, `mn`, `mx`, …) so callers know what to pass.
2. **Initialises every BEGIN-time variable it touches in END.** `awk -W lint` (gawk's pedantic mode) is run against the file in [`tests/test_module_contracts.sh::test_awk_files_pass_lint`](../../tests/test_module_contracts.sh) with all `-v` args supplied; the test asserts zero warnings on empty input.
3. **Stays self-contained.** No `awk -e prelude.awk -f main.awk` chains. If a helper is shared, the duplication is acceptable for now (we have one file).
4. **Outputs a fixed format** documented in the file's header so the caller's parser can stay simple — see `numeric_combined.awk`'s "Line 0: HISTOGRAM …" through "Line 8: TREND" comments.

## Testing

- [`tests/test_module_contracts.sh::test_awk_files_pass_lint`](../../tests/test_module_contracts.sh) gates lint cleanliness.
- The behavioural correctness of `numeric_combined.awk` is covered by the pre-existing 81-test [`tests/test_correctness.sh`](../../tests/test_correctness.sh) and the broader 327-test suite — the ENV-123 extract is a pure move, so any behaviour change would surface there.
- Performance: [`tests/bench_large_dataset.sh`](../../tests/bench_large_dataset.sh) (10k rows, ENV-024 threshold 10 s) measures end-to-end. The post-extract baseline is ~4.4 s — same envelope as pre-extract.
