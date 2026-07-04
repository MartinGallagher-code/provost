# glean/lib/extract — vendored extract engine

This directory is a **vendored copy** of the extract engine + all strategies
from the top-level `EnvoyExtract/` project. `glean` runs it in-process (via the
`--emit-meta` contract) to auto-detect the format of captured output.

**Do not hand-edit files here.** During the migration (proposal 0001, Phases
2–4) `EnvoyExtract/` is the source of truth. To pull upstream changes:

```bash
bash glean/tools/sync-extract.sh          # refresh from repo's EnvoyExtract/
bash glean/tools/sync-extract.sh --runtime-only   # engine only, skip tests/samples
```

`VENDOR.json` records the source git SHA, sync timestamp, and file/strategy
counts so drift from upstream is visible.

After the Phase-5 hard cut, `EnvoyExtract/` is deleted and this becomes the
canonical location; the sync script is retired then.

## Layout (mirrors upstream)

| Path | Purpose |
|---|---|
| `envoy-extract` | engine entry point (invoked internally by `glean`) |
| `lib/` | engine libraries (dispatch, format, postprocess, …) |
| `strategies/` | the 200+ format-detection strategies |
| `samples/` | sample inputs used by the strategy tests |
| `tests/` | the strategy + engine test suite (`bash tests/run_tests.sh`) |
