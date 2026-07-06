# glean/extract — the extract engine

This directory holds glean's extract engine + all strategies. `glean` runs it
in-process (via the `--emit-meta` contract) to auto-detect the format of captured
output.

The engine sources cross-suite shared libraries (version, progress, pager, …)
from its sibling `../lib` — i.e. **`glean/lib/`**.

**This is first-party glean code — edit it here.** The tree was originally
imported from the Envoy suite's `EnvoyExtract/` project, but it is now maintained
in this repo directly; there is no live upstream sync. Add a new format-detection
strategy under `strategies/` with its sample + golden fixtures, then run the suite:

```bash
bash glean/extract/tests/run_tests.sh     # strategy + engine suite
```

`tools/new_strategy.sh` and `tools/review_strategy.sh` scaffold and check a new
strategy.

## Layout

| Path | Purpose |
|---|---|
| `envoy-extract` | engine entry point (invoked internally by `glean`) |
| `lib/` | engine libraries (dispatch, format, postprocess, …) |
| `strategies/` | the 200+ format-detection strategies |
| `tools/` | strategy-authoring helpers (`new_strategy.sh`, `review_strategy.sh`) |
| `samples/` | sample inputs used by the strategy tests |
| `tests/` | the strategy + engine test suite (`bash tests/run_tests.sh`) |
| `../lib/` (`glean/lib/`) | shared suite libs the engine sources via `../lib` |
