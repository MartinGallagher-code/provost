# provost

[![CI](https://github.com/MartinGallagher-code/provost/actions/workflows/ci.yml/badge.svg)](https://github.com/MartinGallagher-code/provost/actions/workflows/ci.yml)
[![PyPI](https://img.shields.io/pypi/v/provost)](https://pypi.org/project/provost/)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)
[![REUSE status](https://api.reuse.software/badge/github.com/MartinGallagher-code/provost)](https://api.reuse.software/info/github.com/MartinGallagher-code/provost)

**Turn command output into data.** Run a command, and provost captures its
output, auto-detects the format, and files it as a tidy, one-row-per-record
dataset in a git-backed store — every capture a commit, every row traceable to
its source.

> Beta. provost is the simplified, single-tool successor to the three-binary
> Envoy suite — see
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

free -m | provost                # capture stdin → auto-detect → tidy dataset 'free'
provost run df -h                # capture a command's output → dataset 'df'
provost ls                       # list datasets
provost show df                  # present a dataset (leading #N = row index)
provost source 5                 # the original input behind row #5
provost stats df                 # statistics on the dataset
```

## What it does

```
run/inject  →  auto-detect (generic parsers + hint rules)  →  tidy melt  →  git-backed store
```

- **Auto-capture format** — ~110 generic format parsers (delimited and
  structured), a declarative hints table, and ~145 tool-specific strategies
  recognise JSON, tables, logs, and system-tool output (`df`, `ps aux`,
  `free`, `mount`, `docker`, …).
- **Named datasets** — `provost run CMD` files into a dataset named after the
  command (looking through `sudo`, `env`, `timeout`, …); piped input is named
  after the parser that recognised it; `--name NAME` overrides either.
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
| `provost run [--] <cmd>` | capture a command's output as a commit, into dataset `<cmd>` |
| `<cmd> \| provost` / `provost [FILE]` | inject stdin / a file |
| `… --name NAME` | file into dataset `NAME` (inject/run) |
| `… --sync` / `--async` | foreground / background capture (default: background only at a terminal) |
| `… --plugin-dir <dir>` | extra strategy dir for this capture (inject/run) |
| `provost source <#N>` | original source behind a dataset row |
| `provost control [<dir>]` / `uncontrol` / `instances` | per-directory capture instances |
| `provost export [<file>]` / `import <file> [<dest>]` | portable store bundle |
| `provost log [--failed]` / `restore <id\|latest>` | capture history (or failed background captures) / bring one back up |
| `provost ls` / `show <name>` / `stats <name>` | datasets |
| `provost triage` | low-confidence / unmatched bucket |
| `provost doctor` | engine + store check |
| `provost help` / `<command> --help` | usage |

## Layout

```
provost/
├── provost               # the single entry point
├── extract/            # extract engine, 265 strategies (~116 generic), hints.tsv
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
  engine's `~/.config/provost/strategies` user dir needed. The winning plugin dir is
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
| `PROVOST_ASYNC` | unset | `1` always background, `0` always foreground; unset = background only at a terminal |
| `PROVOST_MULTI` | `0` | file every dataset an input holds (same as `--multi`) |
| `PROVOST_AUTO_MULTI` | `1` | segment a parse the quality gate would hold, when the parts are clearly better (`0` = hold it; same as `--no-auto-multi`) |
| `PROVOST_MODEL` | `0` | `1` = when the gate would still hold a parse, try the learned layout model and file its table if it passes the same gate (needs `python3`; same as `--model`) |
| `PROVOST_MAX_INPUT` | `10485760` | max input bytes (inject and `run`) |
| `PROVOST_LOCK_TIMEOUT` | `30` | seconds to wait for the store lock |
| `PROVOST_LOCK_MAX_AGE` | `3600` | seconds after which a lock is presumed stale |
| `PROVOST_RECONCILE_OVERLAP` | `60` | % column overlap to union vs split a variant |
| `PROVOST_QUIET` | `0` | `1` suppresses progress/ok messages (same as `--silent`) |

## Tests

```bash
bash tests/smoke.sh                  # end-to-end
bash transform/tests/test_melt.sh    # transform unit tests
bash extract/tests/run_tests.sh      # extract strategies + engine
bash analyze/tests/run_tests.sh      # analyze engine
bash tests/corpus/run.sh --golden    # tidy output of ~3,500 real tools vs goldens
python -m pytest                     # PyPI launcher (100% coverage enforced)
```

All six run in CI (`.github/workflows/ci.yml`).

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

Full text: the `LICENSE` file at the repository root, or
<https://www.gnu.org/licenses/gpl-3.0.html> — SPDX identifier
`GPL-3.0-or-later`. This repository follows the
[REUSE Specification](https://reuse.software/): source files carry SPDX
copyright and licence headers, and the licence text lives in `LICENSES/`.
