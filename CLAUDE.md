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
bash tests/smoke.sh                 # end-to-end (58 checks)
bash transform/tests/test_melt.sh   # transform unit test (10 checks)
```

When you change `src/glean_data/` (the PyPI launcher) or `pyproject.toml`, run
`python -m pytest` — 100% line+branch coverage of `glean_data` is enforced
(`--cov-fail-under=100`, CI `python-package` job).

When you change the `extract/` or `transform/` trees (e.g. add an extract
strategy), run that tree's suite:

```bash
bash extract/tests/run_tests.sh     # strategy + engine suite (CI-enforced)
```

When you touch `analyze/`, run its suite the way CI does (it installs `gawk`
first — see the `analyze-engine` job in `.github/workflows/ci.yml`):

```bash
ENVOY_ANALYZE_SUPPRESS_AWK_WARNING=1 bash analyze/tests/run_tests.sh
```

Add or update tests to cover any behavior you change. New extract strategies
ship with their own sample + golden fixtures under `extract/`. Prefer, in
order: improving a generic parser (`extract/strategies/delimited/` +
`structured/`), adding a hint row (`extract/hints.tsv`), and only then a
bespoke strategy — and validate hint rows with `tests/corpus/run.sh --golden`.

## Conventions

- First-party code is Bash; keep it POSIX-ish and **mawk-safe** (no gawk-only
  awk features) so it runs anywhere — CI covers this.
- glean's user-facing env vars are all `GLEAN_*`; keep it that way.
- glean must run correctly when invoked via `GLEAN_ROOT` — the smoke test guards this.

## Git practices (READ THIS — avoids the mistakes we kept making)

This repo runs in an **ephemeral remote container** that can roll the local
clone back to an older snapshot mid-session. That single fact caused every git
problem we hit. Follow these rules and they don't recur:

1. **Set the commit identity at the start of every session, before the first
   commit.** A fresh clone resets `user.email` to the account default, which
   produces "Unverified" commits. Run once up front (and again after any
   suspected rollback):
   ```bash
   git config user.email noreply@anthropic.com
   git config user.name  "Claude"
   ```
2. **Only pushed commits are safe.** Because the container can revert the local
   tree, `commit` alone is not durable — a rollback silently discards unpushed
   work. Commit *and* `git push -u origin <branch>` after each self-contained
   step, not once at the end.
3. **Recover from a rollback with the remote, never by redoing work.** If HEAD
   or `origin/main` looks stale, the local clone was reset — your pushed commits
   still exist on the remote. Restore with:
   ```bash
   git fetch origin <branch> && git reset --hard origin/<branch>
   ```
4. **Subagents must never run git.** A subagent running `git stash`/`reset`/
   `checkout` in the shared working tree once wiped uncommitted work for the
   whole session. Keep all git operations in the main agent; give subagents
   read-only or file-scoped tasks.
5. **Never commit a broken corpus regen.** `tests/corpus/run.sh --update-golden`
   *deletes* the golden of any tool whose output stopped being tidy — a deleted
   golden for a still-listed tool is a **regression**, not an intended change.
   After regenerating, check `git status` for `D tests/corpus/expected/*.tsv`
   against the manifest and run `bash tests/corpus/run.sh --golden` (0 failed)
   before committing.
