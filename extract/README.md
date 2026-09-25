# provost/extract — the extract engine

This directory holds provost's extract engine + all strategies. `provost` runs it
in-process (via the `--emit-meta` contract) to auto-detect the format of captured
output.

The engine sources cross-suite shared libraries (version, progress, pager, …)
from its sibling `../lib` — i.e. **`provost/lib/`**.

**This is first-party provost code — edit it here.** The tree was originally
imported from the Envoy suite's `EnvoyExtract/` project, but it is now maintained
in this repo directly; there is no live upstream sync. Add a new format-detection
strategy under `strategies/` with its sample + golden fixtures, then run the suite:

```bash
bash provost/extract/tests/run_tests.sh     # strategy + engine suite
```

`tools/new_strategy.sh` and `tools/review_strategy.sh` scaffold and check a new
strategy.

## Layout

| Path | Purpose |
|---|---|
| `envoy-extract` | engine entry point (invoked internally by `provost`) |
| `lib/` | engine libraries (dispatch, format, postprocess, …) |
| `strategies/` | the 257 format-detection strategies, in 15 category dirs (111 generic format parsers in `delimited/` + `structured/`) |
| `tools/` | strategy-authoring helpers (`new_strategy.sh`, `review_strategy.sh`) |
| `samples/` | sample inputs used by the strategy tests |
| `tests/` | the strategy + engine test suite (`bash tests/run_tests.sh`) |
| `../lib/` (`provost/lib/`) | shared suite libs the engine sources via `../lib` |

## Strategy count

257 strategy files (`ls strategies/*/*.sh | wc -l`): delimited 86, system 57,
network 31, structured 25, security 10, filesystem 8, build 7, misc 7,
database 6, hardware 6, packages 6, scientific 5, cloud 1, container 1,
profiling 1. Re-count after adding or removing one — the number is only true
when it is counted. Every strategy has a `## Sample:` file under `samples/`
and a golden under `tests/golden/`; `tests/verify_strategy_outputs.sh`
fails (rather than skips) when either is missing.
