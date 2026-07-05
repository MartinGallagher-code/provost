# Handoff — EnvoyAnalyze/lib

## Status: Stable (v3.0)

Shared library modules sourced by `envoy-analyze`. Each file is prefixed with `_` and sourced at startup.

## Modules

| File | Purpose |
|------|---------|
| `_helpers.sh` | String utilities, escaping, delimiter detection, common helpers (`err`, `normalize_list`, `trim`, `detect_delim`, `json_escape`, `AWK_ISMISSING`) |
| `_csv.sh` | RFC 4180 CSV-to-TSV preprocessing (BOM stripping, quoted fields, embedded commas/newlines) |
| `_profile.sh` | Save/load analysis selection profiles (name validation, error handling) |
| `_format.sh` | Output formatting (plain, JSON, CSV, TSV) |
| `_numeric.sh` | Per-column numeric analyses — combined single-pass awk (summary stats, histogram, sparkline, anomaly detection, distribution shape, trend, bimodality, Benford, monotonicity, Welford's algorithm) |
| `_categorical.sh` | Per-column categorical analyses (top values, category dominance, group summaries, Cramer's V) |
| `_correlation.sh` | Cross-column correlation analyses (correlation matrix, strongest pairs, regression, pairwise completeness, outlier co-occurrence, column correlation strength) |
| `_quality.sh` | Data quality and diagnostics (zero-variance, quality score, suggested drops, near-constant/duplicate detection, noisy items) |
| `_globals.sh` | Global variable registry (documentation only, not sourced at runtime) |

## Conventions

- All modules are sourced by `envoy-analyze` (except `_globals.sh` which is documentation-only)
- Functions are not namespaced — kept flat for simplicity since `envoy-analyze` is the sole consumer
- Heavy computation uses single-pass awk to minimize I/O

## Pending

- None — all modules stable since v3.0
