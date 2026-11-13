# Project Instructions — provost

`provost` turns command output into data: capture a command's output, auto-detect
its format, and present it as a tidy, git-backed dataset. Single entry point:
[`provost`](provost). Design rationale: [docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md).

## Every task is a ticket

Everything done here goes through a ticket in `MartinGallagher-code/shared_tools`,
which keeps every project's tickets as files and moves each one Backlog → In Progress
→ Review → Done (Adversarial Test only when the owner asks). Before any change:

1. Attach `MartinGallagher-code/shared_tools` with `add_repo` and push access, and
   clone it. If a clone is already here, pull it instead
   (`git -C <shared_tools clone> pull --ff-only`): a stale clone has a stale
   `CLAUDE.md` and a stale `ticket.py`.
2. Read the "Every task is a ticket" section of its `CLAUDE.md`. It sets out what each
   column requires, and none of it is optional.
3. Open the ticket with the shared_tools clone's script, not a path in this
   repository:

   ~~~bash
   <shared_tools clone>/scripts/ticket.py new provost "Imperative title" --request "the request, in the user's own words"
   ~~~

**Every change moves the version**, however small: a pull request into `main` raises
it in every place it is written and opens `CHANGELOG.md` with that version's own
dated section, never an "Unreleased" heading left for later. CI fails a pull request
whose version is not greater than its base branch's. This file's own section on the
version says where it is written.

The board: https://claude.ai/artifact/HrB3RpVpqGGQS7UZgZsMJm

## Repository layout

| Path | What it is | Edit here? |
|---|---|---|
| `provost` | the tool (all first-party logic) | **yes** |
| `extract/` | extract engine + strategies | **yes** |
| `analyze/` | analyze engine | **yes** |
| `transform/` | tidy-melt transform | **yes** |
| `lib/` | shared suite libs (`provost_*.sh`) | **yes** |
| `tests/`, `transform/tests/` | first-party tests | **yes** |
| `ml/` | layout-model training tools (dev-only, not shipped; see `ml/README.md`) | **yes** |
| `extract/model/` | the layout model's capture-time runtime + exported trees (shipped; rebuild with `ml/export_model.py`) | **yes** |
| `extract/llm/` | LLM-written parsing templates (`--llm`): the template engine, the prompt Claude writes them from, and the shipped templates | **yes** |

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

> The inherited `envoy-*` / `ENVOY_*` / `MFE_*` names were renamed on 2026-10-02:
> the engines are `extract/provost-extract` and `analyze/provost-analyze`, the libs
> `lib/provost_*.sh`, and every engine setting is `PROVOST_*`. 2.1.0 still honoured
> the old names; the fallbacks were removed after it (2026-10-16) and ship removed in
> 2.2.0. `tests/corpus/*/envoy-*` are captures of the real Envoy proxy's tools:
> leave those names alone.

## Documentation

For every change, add a section at the top of `CHANGELOG.md` (root), newest
first, headed with the version the change moves to, the date, a summary and the
ticket — `## X.Y.Z — YYYY-MM-DD — summary (PV-NNN)` — noting what changed and
which files (see "Every change moves the version" below). Entries from before
2.4.0 are headed by their date alone; leave them as they are. Keep `HANDOFF.md`
current (rewrite to reflect the present state + next steps). These are the two
required docs; a decision worth preserving can also go in `CHANGELOG.md`.

## Every change moves the version

The owner's rule (shared_tools BN-002): **whenever this project changes, its version
changes with it**, however small the change: code, tests, docs or CI. A pull request
into `main` carries its own bump and its own `CHANGELOG.md` section, never an
"Unreleased" heading left for later.

- Patch for fixes, docs, tests and CI; minor for anything new a user can use; major
  only when something that worked stops working the way it did.
- In the same pull request: `VERSION` (the one source: `pyproject.toml`, the wheel
  and `provost --version` read it) and the `.TH` line of `man/provost.1` (the version,
  and the date), and a `## X.Y.Z — YYYY-MM-DD — summary (PV-NNN)` section at the top
  of `CHANGELOG.md`. `tests/check_version.sh` fails if any of them disagree.
- The **version** job in CI fails a pull request whose version is not greater than its
  base branch's, and a push to `main` whose version is not greater than what `main` had
  before it. If `main` moves while a pull request is open, rebase and bump again.
- Publishing is a separate step, and a person's call: run "Release to PyPI"
  (`release.yml`) on `main`, or publish a GitHub release tagged `vX.Y.Z`, not both. A
  number that is never published is fine; a change with no number is not.

## Testing (CI-enforced — see `.github/workflows/ci.yml`)

Every change, of any kind (CI's `version` job; see "Every change moves the
version"):

```bash
bash tests/check_version.sh origin/main   # bumped everywhere, and past main's
```

When you change `provost` or a first-party test, run and keep green:

```bash
bash tests/smoke.sh                 # end-to-end (about 2,000 checks in 33 parts)
bash transform/tests/test_melt.sh   # transform unit test (70 checks)
bash transform/tests/test_units.sh  # --units base: conversion table and rules (86 checks)
```

`tests/smoke.sh` and `extract/tests/run_tests.sh` run in parallel, as the corpus
gate does: one job per CPU (`nproc`), each part's or file's output held and
printed whole, in order. `PROVOST_TEST_JOBS=N` sets the job count, and
`PROVOST_TEST_JOBS=1` runs them one at a time, as they used to (PV-018). In
parallel, a smoke part that runs past `PROVOST_SMOKE_PART_TIMEOUT` seconds (600)
fails by name, after the checks it printed (PV-038). A new
smoke check goes inside an `if _part NAME; then ... fi` block: the one for its
store, or `core` if it uses the default workspace `$WS`, since each part runs
with a fresh one.

When you change `src/provost_data/` (the PyPI launcher) or `pyproject.toml`, run
`python -m pytest` — 100% line+branch coverage of `provost_data` is enforced
(`--cov-fail-under=100`, CI `python-package` job).

When you change the offline install bundle (`tools/offline_bundle.py`,
`tools/offline-install-*.sh`, `docs/offline-install.md`, PV-025), run its unit
tests; CI's `offline bundle` job also builds a real one, validates the SBOM's
schema, signs and verifies `SHA256SUMS`, and installs it with networking off:

```bash
python3 -m unittest discover -s tests/offline_bundle
```

When you change the `extract/` or `transform/` trees (e.g. add an extract
strategy), run that tree's suite:

```bash
bash extract/tests/run_tests.sh     # strategy + engine suite (CI-enforced)
```

When you touch `analyze/`, run its suite (CI runs it under mawk, then gawk —
see the `analyze-engine` job in `.github/workflows/ci.yml`):

```bash
bash analyze/tests/run_tests.sh
```

When you change `ml/`, `extract/model/` or `extract/llm/`, run their stdlib tests (CI-enforced, `quick-checks` job):

```bash
python3 -m unittest discover -s ml/tests
```

When a change can alter tidy output (any parser, `_helpers.sh`, `melt.sh`),
run the corpus gate (CI-enforced) and review every golden it reports:

```bash
bash tests/corpus/run.sh --golden --full   # ~3,500 real tools vs frozen tidy output, and full mode
```

`--full` (PV-037) checks full mode, the path users get: an input whose
full-mode winner is not `--generic`'s must be recorded in
`tests/corpus/full-mode.tsv` with a reason, and keep meeting `expected.tsv`.
After a deliberate change, `run.sh --update-full` rewrites the record and
marks each new row's reason `TODO` until you write it.

Add or update tests to cover any behavior you change. New extract strategies
ship with their own sample + golden fixtures under `extract/`. Prefer, in
order: improving a generic parser (`extract/strategies/delimited/` +
`structured/`), adding a hint row (`extract/hints.tsv`), and only then a
bespoke strategy — and validate hint rows with `tests/corpus/run.sh --golden`.

## Handing this repo over as a bundle

There is no committed bundle any more (the 9.5 MB `bundle.txt` that CI kept in
sync was removed on 2026-10-01 — it rewrote ~10 MB on every commit). Build one
on demand from a clean export when you need it. Shipping a tree to someone
means splitting it into uploadable packets, and this repo is the hardest one
to do that for.

**The procedure lives in `shared_tools/CLAUDE.md`** — clone that repo and read it
before bundling anything. Do not improvise from `merge.sh --help`; the traps are
in the notes, not the usage text. The two facts that cost three round trips the
first time:

- **Do not bundle provost plain-first.** A plain `merge.sh -m 390K` run makes 25
  parts and the upload scanner refuses 15 of them — `tests/corpus/` is ~11,000
  captured outputs from real tools (`vault-*`, `gitleaks-*`, `trufflehog-*`,
  `gpg-list-secret-keys`, `getent-passwd`), and output *about* secrets reads to a
  scanner much like secrets. Base64 the whole tree instead: one round, 49 packets
  on 2026-11-13 (2.22.1: 45 base64 and 4 plain; 58 before PV-042).
- **Hold out files over 290,000 bytes** before encoding. Base64 expands by
  ~1.35x, so a larger file cannot fit a packet and cannot be split either — an
  entry is atomic. Ship those plain. On 2026-11-13 (2.22.1) that is four files:
  `ml/eval/llm-labels-2026-10-23.jsonl.gz`, `extract/model/layout-model.json.gz`,
  `CHANGELOG.md` and `provost`, with `tests/smoke.sh` (289,035 bytes) next. Take it
  from `find -size +290000c` rather than from this list: they are files that grow.
  The plain parts holding the two `.gz` files come out at 930 KB and 960 KB, above
  the 880 KB the shared_tools notes have seen import.

`shared_tools/CLAUDE.md` carries the exact commands, the verified packet count,
and the reason each step is there.

## Conventions

- First-party code is Bash; keep it POSIX-ish and **mawk-safe** (no gawk-only
  awk features) so it runs anywhere — CI covers this.
- provost's user-facing env vars are all `PROVOST_*`; keep it that way.
- provost must run correctly when invoked via `PROVOST_ROOT` — the smoke test guards this.

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
