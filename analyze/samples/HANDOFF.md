# Handoff — EnvoyAnalyze/samples

## Overview

Sample CSV datasets for testing and demonstrating envoy-analyze and envoy-browse.

## Files

- `trees.csv` — R "trees" dataset (31 rows, 4 numeric columns: Index, Girth, Height, Volume)
- `anscombe.csv` — Anscombe's quartet (categorical "data" column + numeric x/y)
- `biostats.csv` — Small biostats sample (mixed categorical + numeric: Name, Sex, Age, Height, Weight)
- `edge.csv` — Synthetic edge cases (5 rows: zero-variance column, missing values)
- `known.csv` — Known-answer dataset (x=1..10, y=10x, constant=5) for correctness tests
- `missing.csv` — Missing value edge cases (10 rows, 4 cols; all 12 missing forms: empty, NaN, null, None, NULL, NA, N/A, #N/A, nan, none, `-`, `.`)
- `numeric_edge.csv` — Numeric edge cases (5 rows: x, neg=-x, sci=10x scientific, big=1Mx); hand-calculated: mean(x)=3, corr(x,neg)=-1, corr(x,sci)=1
- `bimodal.csv` — Distribution tests (20 rows: bimodal column with two clusters, skewed column, Benford-distributed column)
- `quoted.csv` — RFC 4180 CSV quoting (embedded commas, escaped quotes, embedded newlines, empty quoted fields)
- `large_vals.csv` — Welford's algorithm verification (10 rows near 1e9 with small variance; proves naive formula fails)
- `known_benford.csv` — 200 rows; `benford` column drawn log-uniform (chi² = 2.68, PASS) and `uniform` column drawn uniform (chi² = 51.02, FAIL). Used by `test_known_values_extended.sh` (ENV-124).
- `known_categorical.csv` — 60 rows, three categorical columns. Hand-computed Cramer's V(device, os) = 0.7643; sparse cells trip the expected-frequency-<5 warning. (ENV-124)
- `known_spearman.csv` — 15 rows. `x` strict ascending, `y = x²`, `z = -x`, `noisy` = `x` with one adjacent-pair swap. Spearman ρ values: x = +1.0, z = -1.0, noisy = 0.996429 (pins tie-handling). (ENV-124)
- `known_bimodal_seeded.csv` — 50 rows, two well-separated clusters (~10 / ~90). Detector reports YES with peak heights 24, 22. (ENV-124)

## Notes

- All files have a header row as required by envoy-analyze
- `edge.csv` is used for regression tests (correlation bounds, zero-variance, missingness)
- `known.csv` is used by `test_correctness.sh` for exact value verification
- `missing.csv`, `numeric_edge.csv`, `bimodal.csv`, `quoted.csv`, `large_vals.csv` added in v0.7
- `known_benford.csv` / `known_categorical.csv` / `known_spearman.csv` / `known_bimodal_seeded.csv` added in ENV-124. Generator script: [`../tests/_compute_known_truths.py`](../tests/_compute_known_truths.py) — re-run with `--emit samples` to regenerate, or `--print` to dump the truth table the tests assert against.
