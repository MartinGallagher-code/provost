# Project Instructions — glean

`glean` turns command output into data: capture a command's output, auto-detect
its format, and present it as a tidy, git-backed dataset. Single entry point:
[`glean`](glean). Design rationale: [docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md).

## Repository layout

| Path | What it is | Edit here? |
|---|---|---|
| `glean` | the tool (all first-party logic) | **yes** |
| `extract/` | extract engine + strategies | **yes** |
| `analyze/` | analyze engine | **yes** |
| `transform/` | tidy-melt transform | **yes** |
| `lib/` | shared suite libs (`envoy_*.sh`) | **yes** |
| `tests/`, `transform/tests/` | first-party tests | **yes** |

### Standalone — everything here is first-party, edit it in place

This is a **standalone repository with no live tie to Envoy.** `extract/`,
`analyze/`, `transform/`, and `lib/` were originally imported from the Envoy
suite, but they are now maintained here directly — treat them as first-party
code and edit them in place. Add extract strategies under
`extract/strategies/`, wire analyze features under `analyze/`, and so on, without
regard to upstream Envoy.

The old `tools/sync-*.sh` re-vendoring scripts and the `VENDOR.json` provenance
files have been removed; the original import point is recorded in `CHANGELOG.md`
if it's ever needed. Any future re-integration with Envoy will be a deliberate,
manual merge — not a routine sync.

> The `envoy-*` names and `envoy_*.sh` libs inside these trees are retained as-is
> (renaming them is a large, separate change) — they are simply glean's internals now.

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

When you change the `extract/` or `transform/` trees (e.g. add an extract
strategy), run that tree's suite:

```bash
bash extract/tests/run_tests.sh     # strategy + engine suite (CI-enforced)
```

The analyze suite (`analyze/tests/`) still ships tests for the `browse` /
`dashboard` surfaces that glean intentionally does **not** include, so the raw
`analyze/tests/run_tests.sh` is red out of the box. CI runs a filtered subset
that skips those (and installs `gawk`) — see the `analyze-engine` job in
`.github/workflows/ci.yml`; run analyze tests the same way if you touch `analyze/`.

Add or update tests to cover any behavior you change. New extract strategies
ship with their own sample + golden fixtures under `extract/`.

## Conventions

- First-party code is Bash; keep it POSIX-ish and **mawk-safe** (no gawk-only
  awk features) so it runs anywhere — CI covers this.
- glean's user-facing env vars are all `GLEAN_*`; keep it that way.
- glean must run correctly when invoked via a symlink on `PATH` (it resolves its
  own directory via `GLEAN_ROOT`) — `install.sh` and the smoke test guard this.
