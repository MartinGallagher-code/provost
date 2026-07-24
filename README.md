# glean

[![CI](https://github.com/MartinGallagher-code/glean/actions/workflows/ci.yml/badge.svg)](https://github.com/MartinGallagher-code/glean/actions/workflows/ci.yml)
[![PyPI](https://img.shields.io/pypi/v/glean-data)](https://pypi.org/project/glean-data/)
[![License: GPL-3.0-only](https://img.shields.io/badge/License-GPL--3.0--only-blue.svg)](LICENSE)
[![REUSE status](https://api.reuse.software/badge/github.com/MartinGallagher-code/glean)](https://api.reuse.software/info/github.com/MartinGallagher-code/glean)

**Turn command output into data.** Run a command, and glean captures its
output, auto-detects the format, and files it as a tidy, one-row-per-record
dataset in a git-backed store — every capture a commit, every row traceable to
its source.

> Prototype (proposal 0001) — the simplified successor to the three-binary
> Envoy suite, as one tool. See
> [docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md).

## Install

```bash
pip install glean-data
```

The PyPI package (`glean-data`; the import name `glean` was taken) bundles the
complete tool — the `glean` entry point plus its extract/analyze/transform
engines — and a thin Python launcher execs it in place. Requires bash and git.

## Quick start

```bash
glean doctor                   # check engines + store

free -m | glean                # capture stdin → auto-detect → tidy dataset
glean run df -h                # capture a command's output as a commit
glean ls                       # list datasets
glean show df                  # present a dataset (leading #N = row index)
glean source 5                 # the original input behind row #5
glean stats df                 # statistics on the dataset
```

## What it does

```
run/inject  →  auto-detect (generic parsers + hint rules)  →  tidy melt  →  git-backed store
```

- **Auto-capture format** — ~29 generic format parsers (plus a declarative
  hints table and a tail of bespoke strategies) recognise JSON, tables,
  logs, and system-tool output (`df`, `ps aux`, `free`, `mount`, `docker`, …).
- **Present a dataset** — a wide `entry<N>.field` extract is melted to one row
  per record; same-typed captures reconcile into one table.
- **Git core** — the store is a git repo; every capture is a commit tagged
  `capture-<id>`. `glean log` lists them, `glean restore <id>` brings one back up.
- **Provenance** — every dataset row has a globally-unique visible `#N`;
  `glean source N` shows the exact captured input that produced it.
- **Global or per-directory** — captures go to a global store (`~/.glean`) by
  default; `glean control <dir>` makes a directory its own instance.
- **Portable** — `glean export` bundles the store; `glean import` reopens it
  elsewhere. Datasets, history, and provenance all survive the move.
- **Analyze** — `glean stats <dataset>` runs the vendored analyze engine.

## Command reference

| Command | Purpose |
|---|---|
| `glean run [--] <cmd>` | capture a command's output as a commit |
| `<cmd> \| glean` / `glean [FILE]` | inject stdin / a file |
| `… --plugin-dir <dir>` | extra strategy dir for this capture (inject/run) |
| `glean source <#N>` | original source behind a dataset row |
| `glean control [<dir>]` / `uncontrol` / `instances` | per-directory capture instances |
| `glean export [<file>]` / `import <file> [<dest>]` | portable store bundle |
| `glean log` / `restore <id\|latest>` | capture history / bring one back up |
| `glean ls` / `show <name>` / `stats <name>` | datasets |
| `glean triage` | low-confidence / unmatched bucket |
| `glean doctor` | engine + store check |

## Layout

```
glean/
├── glean               # the single entry point
├── extract/            # extract engine, ~40 generic + ~130 bespoke strategies, hints.tsv
├── analyze/            # analyze engine
├── transform/          # tidy-melt transform
├── lib/                # shared suite libraries
├── completions/, man/  # bash completion, man page
└── tests/              # smoke + unit tests
```

## Standalone repository

This tree is fully self-contained: `glean` resolves its engines from its own
directory, so it runs with no external dependencies. The `extract/`, `analyze/`,
`transform/`, and `lib/` trees were originally imported from the Envoy suite but
are now **first-party glean code, maintained here directly** — there is no live
tie to upstream Envoy. Add extract strategies under `extract/strategies/` and
edit the engines in place; run each tree's own test suite to keep it green.

## Integrating from another tool

Wrappers that pipe into glean (e.g. deframe) get two hooks:

- **`--plugin-dir <dir>`** (or `GLEAN_PLUGIN_DIR`): an extra strategy directory
  that competes in format detection for that capture — no symlink into the
  engine's `~/.mfe/strategies` user dir needed. The winning plugin dir is
  recorded in the capture's metadata.
- **`#%` metadata prologue**: a leading run of `#%` lines on injected input is
  capture context, not data. It is peeled off before detection (so it can never
  corrupt the generic parsers), stored with the capture as `context.txt`, and
  `glean source` still shows the original input verbatim. A `#%` line after the
  first data line is data and passes through untouched — so context no longer
  has to travel out-of-band in a run manifest.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `GLEAN_HOME` | `~/.glean` | global store directory |
| `GLEAN_WORKSPACE` | — | explicit store override (wins) |
| `GLEAN_MIN_CONFIDENCE` | `50` | commit threshold (0–100) |
| `GLEAN_PLUGIN_DIR` | — | extra strategy dir for detection (same as `--plugin-dir`) |
| `GLEAN_MAX_INPUT` | `10485760` | max input bytes |
| `GLEAN_LOCK_TIMEOUT` | `30` | seconds to wait for the store lock |
| `GLEAN_RECONCILE_OVERLAP` | `60` | % column overlap to union vs split a variant |

## Tests

```bash
bash glean/tests/smoke.sh              # end-to-end (58 checks)
bash glean/transform/tests/test_melt.sh  # transform unit tests (10 checks)
python -m pytest                       # PyPI launcher (100% coverage enforced)
```
