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

```bash
pip install provost[lm]
```

This adds a better reader for `--model`: a tiny pretrained language model
fine-tuned on provost's own labels. It comes as the
[`provost-model`](https://github.com/MartinGallagher-code/provost_model)
package (85 MB) and runs on numpy, with no torch or GPU. Without it,
`--model` uses the small decision trees provost ships.

**No network?** Each release from 2.6.0 on has an offline bundle attached to
its [GitHub release](https://github.com/MartinGallagher-code/provost/releases):
the wheel, the sdist, a CycloneDX SBOM, `SHA256SUMS` and a Sigstore signature
for every file, for an air-gapped host. Verify it, carry it across, then
`pip install --no-index --find-links . provost`. The steps:
[docs/offline-install.md](docs/offline-install.md).

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

- **Auto-capture format** — ~118 generic format parsers (delimited and
  structured), a declarative hints table, and ~155 tool-specific strategies
  recognise JSON, tables, logs, and system-tool output (`df`, `ps aux`,
  `free`, `mount`, `docker`, …), HPC benchmark and fabric output (OSU, IOR,
  mdtest, HPL, HPCG, STREAM, fio, iperf3, lnet_selftest, ibstat, perfquery),
  Slurm (`sacct`, `sacct -p`, `sinfo`, `squeue`), ReFrame perflogs and JUnit
  XML.
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
| `provost batch FILE... [--from LIST]` | inject many files as one commit, a capture each, parsed in parallel (`-j N`) |
| `provost listen <cmd>` / `unlisten <cmd>` | capture `<cmd>` every time it runs (output still on screen) |
| `… --name NAME` | file into dataset `NAME` (inject/run) |
| `… --show` | show the output as well as filing it (inject/run) |
| `… --sync` / `--async` | foreground / background capture (default: background only at a terminal) |
| `… --plugin-dir <dir>` | extra strategy dir for this capture (inject/run) |
| `… --context-columns` | each `key=value` in a `#%` prologue becomes a column on every row (inject/batch) |
| `… --env` | record where the capture was taken (host, kernel, OS, modules, Slurm job, user, allow-listed variables) in its `#%` prologue (`--env=modules`: and the kernel modules) |
| `provost ls` / `show <name>` / `stats <name>` | datasets (`show --capture ID`: one capture's rows; `--at ID`: as it stood then) |
| `provost search <pattern> [name...]` | `git grep` over the rows (`--output`: raw outputs; `--files`: run files; `--at ID`) |
| `provost source <#N \| ID>` | original source behind a dataset row, or a capture |
| `provost check-manifest [ID\|NAME...]` | which captures lack required run-manifest keys (`--post`, `--strict`, `--profile P`) |
| `provost annotate ID KEY=VALUE...` | add post-run keys (reviewer, disposition) to a capture |
| `provost diff [name] [A [B]]` | rows and run files that changed between two captures |
| `provost log [--failed]` / `restore <id\|latest>` / `prev` / `next` | capture history / move the store to a capture and back |
| `provost control [<dir>]` / `uncontrol` / `instances` | per-directory capture instances (each run keeps the directory's files) |
| `provost files [ID] [path] [--to dir]` | a controlled directory's files as a capture kept them |
| `provost export [<file>]` / `import <file> [<dest>]` | portable store bundle |
| `provost triage` | low-confidence / unmatched bucket |
| `provost doctor` | engine + store check |
| `provost verify [--capture ID]` | store integrity: `git fsck`, each capture's output against its recorded sha256, tags, id gaps |
| `provost help` / `help advanced` / `<command> --help` | short help / full reference / one command's usage |

Every dataset row carries `#` (its number in the store), `capture` (the
capture it came from, e.g. `c0007`) and, for records, `n` (its place in that
capture). A tool's own column named `#` (zypper's repo number, a template's
row index) is filed as `#_2`, so it never shares a name with the store's, and
the capture's `meta.tsv` says so (`renamed_columns  NAME:#=#_2`).

## Layout

```
provost/
├── provost               # the single entry point
├── extract/            # extract engine, 274 strategies (~118 generic), hints.tsv
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
  has to travel out-of-band in a run manifest. With **`--context-columns`**
  (or `PROVOST_CONTEXT_COLUMNS=1`) each `key=value` word in it is also put on
  every row the capture files, after `#` and `capture`: `#% host=web03
  rack=r2` gives each row `host` and `rack` columns. A data column of the same
  name keeps it and the context one becomes `_host` (the rule `capture` already
  follows), and the capture's `meta.tsv` records which columns came from the
  context (`context_columns  host=_host,rack=rack`); a capture held in
  `unsorted` is kept as it came.
- **Run manifest**: agreed `#%` key names (`req`, `test`, `test.version`,
  `build.commit`, `sut`, ... in `extract/manifests/default.tsv`) and a check.
  `provost check-manifest` lists the captures missing a required key;
  `--manifest FILE` prepends and checks one at capture time
  (`--strict-manifest` refuses to file without it); `provost annotate`
  adds the post-run `reviewer` and `disposition`. See `docs/usage.md`.
- **Environment capture (`--env`)**, off unless asked for: the capture's
  prologue gains `env.host`, `env.kernel`, `env.arch`, `env.os`,
  `env.modules` (Lmod's `$LOADEDMODULES`), `env.user`, and inside a Slurm job
  its id (as the manifest's `sched.job`), node list, cluster and partition.
  Environment variables only from the allow-list `PROVOST_ENV_VARS` (default
  `OMP_* MPI_* OMPI_MCA_* I_MPI_* MPICH_* UCX_* CUDA_* NCCL_*`), never all of
  them, and never one whose name or value looks like a secret
  (`extract/secrets.tsv`): that one is named in `env.withheld` instead.
  `--env=modules` adds the kernel modules. See `docs/usage.md`.
- **`provost batch FILE... [--from LIST]`**: many inputs, one commit. Each file
  is a capture of its own — its own id, its own `provost source`, its own
  `capture-<id>` tag — but they are parsed in parallel (`-j N`, default the
  CPUs, at most 16) and filed under one hold of the store lock, so capturing
  a 50-host fleet costs one commit rather than fifty serialised ones. Ids
  follow the order the files were named. `--name NAME` applies to the files
  after it; `--from LIST` reads `PATH` or `NAME<TAB>PATH` lines. A fleet
  wrapper writes one file per host opening with `#% host=NAME` and passes
  `--context-columns`, and every row says which host it came from.

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
| `PROVOST_CONTEXT_COLUMNS` | `0` | `1` = each `key=value` word of a `#%` prologue becomes a column on the capture's rows (same as `--context-columns`) |
| `PROVOST_MANIFEST_PROFILE` | unset | run-manifest profile (NAME or `.tsv`); when set, every capture is checked |
| `PROVOST_MANIFEST_STRICT` | `0` | `1` = refuse a capture lacking a required manifest key (`--strict-manifest`) |
| `PROVOST_ENV` | `0` | `1` = record where each capture was taken in its prologue (`--env`); `modules` = and the kernel modules (`--env=modules`) |
| `PROVOST_ENV_VARS` | `OMP_* MPI_* OMPI_MCA_* I_MPI_* MPICH_* UCX_* CUDA_* NCCL_*` | the variables `--env` records: names or glob patterns, space- or comma-separated; set but empty = none |
| `PROVOST_AUTO_MULTI` | `1` | segment a parse the quality gate would hold, when the parts are clearly better (`0` = hold it; same as `--no-auto-multi`) |
| `PROVOST_MODEL` | `0` | `1` = when the gate would still hold a parse, try the learned layout model and file its table if it passes the same gate (needs `python3`; same as `--model`) |
| `PROVOST_LAYOUT_LM` | unset | the tiny LM `--model` labels with: a model directory, or unset for the installed `provost-model` package (`pip install provost[lm]`); `0` = the trees only |
| `PROVOST_PYTHON` | `python3` | the interpreter that runs the layout model (the pip launcher sets it to its own) |
| `PROVOST_LLM` | `0` | `1` = parse with a template Claude wrote for that tool (regexes, or a small boxed Python parser for records that span lines; stored in the store's `llm-templates/`, or shipped), before a generic parse is trusted or a capture held; with no fitting template and an API key, ask Claude to write one. Writing one sends the capture to the Anthropic API, once per tool; lines a template sets aside that still carry a word or a number (titles, version banners, summary counts, errors) are filed beside its datasets as `NAME.notes`, never dropped; later captures of the tool are parsed offline, except one that shows a kind of line the template has not met, which (with a key) is sent once with the template's earlier captures so Claude can extend it (repair; kept only if it still reads them) (same as `--llm`) |
| `PROVOST_LLM_MODEL` | `claude-opus-5-5` | the model that writes templates |
| `PROVOST_LLM_API_KEY` | — | Anthropic API key for `--llm` (else `ANTHROPIC_API_KEY`; prefer this one where `ANTHROPIC_API_KEY` is taken, e.g. in a Claude Code environment, which keeps that name for its own sign-in) |
| `PROVOST_LLM_BASE_URL` | `https://api.anthropic.com` | API base URL |
| `PROVOST_LLM_TEMPLATE_DIRS` | — | colon-separated directories of templates to look in after the store's `llm-templates/` and before the ones shipped with provost |
| `PROVOST_LLM_LOG` | — | a file to append one JSON line per API reply to (purpose, tool, model, token usage), to add up what `--llm` cost |
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
bash tests/check_version.sh          # the version agrees everywhere (see below)
```

All seven run in CI (`.github/workflows/ci.yml`).

## Versioning and support

provost follows semantic versioning from 2.4.0 on, MAJOR.MINOR.PATCH, and every
change moves the version: each pull request merged into `main` carries a new
number and its own `CHANGELOG.md` section, however small the change (patch for
fixes, docs, tests and CI; minor for anything new; major only for a break of
what the promise below covers). Publishing to PyPI is a separate step, so not
every number reaches PyPI.

- **Covered by the promise** (a break needs a new major): the commands and their
  options; exit statuses; the `PROVOST_*` environment variables; the store format
  (a store written by 2.x is read by every later 2.x; a format change ships with
  an automatic migration, as formats 2 and 3 did); the dataset layout (`#`,
  `capture`, `n`, then the data columns) and `provost export` bundles.
- **Not covered**: the exact tidy output provost gives for a particular tool's
  output. Parsers improve in minor releases, so a re-capture can file a better
  table than before; captures already filed never change. Help wording, and
  files inside the store that are not documented, are not covered either.
- **Deprecation**: a name or option is removed only in a major release, after at
  least one minor release that still accepts it and warns. (Before 2.4 this was
  not so: the legacy `ENVOY_*`/`MFE_*` names were dropped in 2.2.0.)
- **Support**: the latest release only. Fixes ship in the next release; there are
  no backports to older minors or majors.

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
