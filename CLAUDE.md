# Project Instructions — glean

`glean` turns command output into data: capture a command's output, auto-detect
its format, and present it as a tidy, git-backed dataset. Single entry point:
[`glean`](glean). Design rationale: [docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md).

## Repository layout

| Path | What it is | Edit here? |
|---|---|---|
| `glean` | the tool (all first-party logic) | **yes** |
| `extract/` | vendored extract engine + strategies (from EnvoyExtract) | no — see below |
| `analyze/` | vendored analyze engine (from EnvoyAnalyze) | no |
| `transform/` | imported tidy-melt transform (from EnvoyCapture) | no |
| `lib/` | vendored shared suite libs (`envoy_*.sh`) | no |
| `tools/` | the `sync-*.sh` re-vendoring scripts | yes |
| `tests/`, `transform/tests/` | first-party tests | yes |

### Vendored trees are canonical here, but do not hand-edit them

`extract/`, `analyze/`, `transform/`, and `lib/` are vendored from the upstream
Envoy repo. In this standalone repo they are the canonical copies, but changes to
them belong **upstream**, then re-synced — do not edit vendored files in place.
To pull upstream changes you need an Envoy checkout:

```bash
ENVOY_EXTRACT_SRC=/path/to/envoy/EnvoyExtract bash tools/sync-extract.sh
ENVOY_ANALYZE_SRC=/path/to/envoy/EnvoyAnalyze bash tools/sync-analyze.sh
ENVOY_CAPTURE_SRC=/path/to/envoy/EnvoyCapture bash tools/sync-melt.sh
```

`VENDOR.json` in each tree records the upstream git SHA it was synced from.

## Documentation

For every change, append a dated entry to `CHANGELOG.md` (root) noting what
changed and which files. Keep `HANDOFF.md` current (rewrite to reflect the
present state + next steps). These are the two required docs; a decision worth
preserving can also go in `CHANGELOG.md`.

## Testing (CI-enforced — see `.github/workflows/ci.yml`)

When you change `glean` or a first-party test, run and keep green:

```bash
bash tests/smoke.sh                 # end-to-end (33 checks)
bash transform/tests/test_melt.sh   # transform unit test (8 checks)
```

When you re-sync a vendored tree, run its suite in place:

```bash
bash extract/tests/run_tests.sh     # strategy + engine suite
```

Add or update tests to cover any behavior you change.

## Conventions

- First-party code is Bash; keep it POSIX-ish and **mawk-safe** (no gawk-only
  awk features) so it runs anywhere — CI covers this.
- glean's user-facing env vars are all `GLEAN_*`; keep it that way.
- glean must run correctly when invoked via a symlink on `PATH` (it resolves its
  own directory via `GLEAN_ROOT`) — `install.sh` and the smoke test guard this.
