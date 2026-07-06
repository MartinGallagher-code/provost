# lib/awk/ — Changelog

## 2026-04-24 (ENV-123: extracted from `lib/_numeric.sh`)
- Created. Holds standalone awk programs invoked by `lib/_*.sh` modules via `awk -f`. Replaces the prior practice of embedding multi-hundred-line awk programs inside bash heredocs.
- Initial contents: `numeric_combined.awk` (~250 lines) — the single-pass per-column numeric analysis previously embedded in `_numeric_combined_awk`. The shim in `lib/_numeric.sh` now just builds the `-v` argument list and invokes `awk -f`.
- Pure move. Awk body is byte-identical apart from the BEGIN-block initialisations added so `awk -W lint` runs clean on empty input. The 9-line output format consumed by `run_numeric_analyses` is unchanged.
- Result: `lib/_numeric.sh` shrunk 611 → 398 lines (under the 400-line AC ceiling). Full EnvoyAnalyze suite 327/327 still green; new `tests/test_module_contracts.sh::test_awk_files_pass_lint` enforces lint cleanliness on every `lib/awk/*.awk`.
