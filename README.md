# provost

[![CI](https://github.com/MartinGallagher-code/provost/actions/workflows/ci.yml/badge.svg)](https://github.com/MartinGallagher-code/provost/actions/workflows/ci.yml)
[![PyPI](https://img.shields.io/pypi/v/provost)](https://pypi.org/project/provost/)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)
[![REUSE status](https://api.reuse.software/badge/github.com/MartinGallagher-code/provost)](https://api.reuse.software/info/github.com/MartinGallagher-code/provost)

**Turn command output into data.** Run a command, and provost captures its
output, auto-detects the format, and files it as a tidy, one-row-per-record
dataset in a git-backed store — every capture a commit, every row traceable to
its source.

> Prototype (proposal 0001) — the simplified successor to the three-binary
> Envoy suite, as one tool. See
> [docs/0001-rename-and-simplification.md](docs/0001-rename-and-simplification.md).

## Install

```bash
pip install provost
```

The PyPI package (`provost`) bundles the
complete tool — the `provost` entry point plus its extract/analyze/transform
engines — and a thin Python launcher execs it in place. Requires bash and git.

## Quick start

```bash
provost doctor                   # check engines + store

free -m | provost                # capture stdin → auto-detect → tidy dataset
provost run df -h                # capture a command's output as a commit
provost ls                       # list datasets
provost show df                  # present a dataset (leading #N = row index)
provost source 5                 # the original input behind row #5
provost stats df                 # statistics on the dataset
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
  `capture-<id>`. `provost log` lists them, `provost restore <id>` brings one back up.
- **Provenance** — every dataset row has a globally-unique visible `#N`;
  `provost source N` shows the exact captured input that produced it.
- **Global or per-directory** — captures go to a global store (`~/.provost`) by
  default; `provost control <dir>` makes a directory its own instance.
- **Portable** — `provost export` bundles the store; `provost import` reopens it
  elsewhere. Datasets, history, and provenance all survive the move.
- **Analyze** — `provost stats <dataset>` runs the vendored analyze engine.

## Command reference

| Command | Purpose |
|---|---|
| `provost run [--] <cmd>` | capture a command's output as a commit |
| `<cmd> \| provost` / `provost [FILE]` | inject stdin / a file |
| `… --plugin-dir <dir>` | extra strategy dir for this capture (inject/run) |
| `provost source <#N>` | original source behind a dataset row |
| `provost control [<dir>]` / `uncontrol` / `instances` | per-directory capture instances |
| `provost export [<file>]` / `import <file> [<dest>]` | portable store bundle |
| `provost log` / `restore <id\|latest>` | capture history / bring one back up |
| `provost ls` / `show <name>` / `stats <name>` | datasets |
| `provost triage` | low-confidence / unmatched bucket |
| `provost doctor` | engine + store check |

## Layout

```
provost/
├── provost               # the single entry point
├── extract/            # extract engine, ~40 generic + ~130 bespoke strategies, hints.tsv
├── analyze/            # analyze engine
├── transform/          # tidy-melt transform
├── lib/                # shared suite libraries
├── completions/, man/  # bash completion, man page
└── tests/              # smoke + unit tests
```

## Standalone repository

This tree is fully self-contained: `provost` resolves its engines from its own
directory, so it runs with no external dependencies. The `extract/`, `analyze/`,
`transform/`, and `lib/` trees were originally imported from the Envoy suite but
are now **first-party provost code, maintained here directly** — there is no live
tie to upstream Envoy. Add extract strategies under `extract/strategies/` and
edit the engines in place; run each tree's own test suite to keep it green.

## Integrating from another tool

Wrappers that pipe into provost (e.g. deframe) get two hooks:

- **`--plugin-dir <dir>`** (or `PROVOST_PLUGIN_DIR`): an extra strategy directory
  that competes in format detection for that capture — no symlink into the
  engine's `~/.mfe/strategies` user dir needed. The winning plugin dir is
  recorded in the capture's metadata.
- **`#%` metadata prologue**: a leading run of `#%` lines on injected input is
  capture context, not data. It is peeled off before detection (so it can never
  corrupt the generic parsers), stored with the capture as `context.txt`, and
  `provost source` still shows the original input verbatim. A `#%` line after the
  first data line is data and passes through untouched — so context no longer
  has to travel out-of-band in a run manifest.

The store itself is plain files (TSV datasets, per-capture `meta.tsv` +
`output.txt`, `provenance.tsv`), so other tools can browse it read-only without
provost installed. [Meridian Commander](https://github.com/MartinGallagher-code/meridian_commander)
ships a **Provost data** plug-in that does exactly that: datasets as scrollable
tables, the capture log, and each row's original input via its `#N` provenance
index — including stores on remote (SFTP/SSH) hosts.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `PROVOST_HOME` | `~/.provost` | global store directory |
| `PROVOST_WORKSPACE` | — | explicit store override (wins) |
| `PROVOST_MIN_CONFIDENCE` | `50` | commit threshold (0–100) |
| `PROVOST_PLUGIN_DIR` | — | extra strategy dir for detection (same as `--plugin-dir`) |
| `PROVOST_MAX_INPUT` | `10485760` | max input bytes |
| `PROVOST_LOCK_TIMEOUT` | `30` | seconds to wait for the store lock |
| `PROVOST_RECONCILE_OVERLAP` | `60` | % column overlap to union vs split a variant |

## Tests

```bash
bash provost/tests/smoke.sh              # end-to-end (58 checks)
bash provost/transform/tests/test_melt.sh  # transform unit tests (10 checks)
python -m pytest                       # PyPI launcher (100% coverage enforced)
```

## License

Copyright (C) 2026 Martin J. Gallagher

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <https://www.gnu.org/licenses/>.

Full text: [LICENSE](LICENSE) — SPDX identifier `GPL-3.0-or-later`. This
repository follows the [REUSE Specification](https://reuse.software/): source
files carry SPDX copyright and licence headers, and the licence text lives in
[`LICENSES/`](LICENSES).
