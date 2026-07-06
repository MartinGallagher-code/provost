# glean

**Turn command output into data.** Run a command, and glean captures its
output, auto-detects the format, and files it as a tidy, one-row-per-record
dataset in a git-backed store — every capture a commit, every row traceable to
its source.

> Prototype (proposal 0001) — the simplified successor to the three-binary
> Envoy suite, as one tool. See
> [docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md).

## Quick start

```bash
bash glean/install.sh          # put `glean` on your PATH (~/.local/bin)
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
run/inject  →  auto-detect (200+ strategies)  →  tidy melt  →  git-backed store
```

- **Auto-capture format** — 200+ extract strategies recognise JSON, tables,
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
├── extract/            # extract engine + 205 strategies
├── analyze/            # analyze engine
├── transform/          # tidy-melt transform
├── lib/                # shared suite libraries
├── completions/, man/  # bash completion, man page
├── install.sh
└── tests/              # smoke + unit tests
```

## Standalone repository

This tree is fully self-contained: `glean` resolves its engines from its own
directory, so it runs with no external dependencies. The `extract/`, `analyze/`,
`transform/`, and `lib/` trees were originally imported from the Envoy suite but
are now **first-party glean code, maintained here directly** — there is no live
tie to upstream Envoy. Add extract strategies under `extract/strategies/` and
edit the engines in place; run each tree's own test suite to keep it green.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `GLEAN_HOME` | `~/.glean` | global store directory |
| `GLEAN_WORKSPACE` | — | explicit store override (wins) |
| `GLEAN_MIN_CONFIDENCE` | `50` | commit threshold (0–100) |
| `GLEAN_MAX_INPUT` | `10485760` | max input bytes |
| `GLEAN_LOCK_TIMEOUT` | `30` | seconds to wait for the store lock |
| `GLEAN_RECONCILE_OVERLAP` | `60` | % column overlap to union vs split a variant |

## Tests

```bash
bash glean/tests/smoke.sh              # end-to-end (32 checks)
bash glean/transform/tests/test_melt.sh  # transform unit tests (8 checks)
```
