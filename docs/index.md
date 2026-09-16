# provost

`provost` turns command output into data: pipe any command's output in, and it
captures the raw text as a git commit, auto-detects the format against a
library of 200+ extract strategies, and files the result as a tidy,
one-row-per-record dataset you can list, show, and analyse.

```console
$ df -h | provost
$ provost ls
DATASET            ROWS
aligned-columns      12
$ provost show aligned-columns
```

Every capture is a commit; every dataset row carries a globally-unique index
(`#N`) that `provost source N` maps back to the exact captured input that
produced it — the raw text is never lost, only organised.

## Install

```console
$ pip install provost
```

The PyPI package bundles the whole tool (a Bash suite) inside a small Python
launcher; the only runtime requirements are `bash` and standard POSIX tools.

## Where to go next

- **[Usage](usage.md)** — every subcommand, flag, and `PROVOST_*` environment
  variable.
- **[Multi-dataset capture](0003-multi-dataset.md)** — why one input can hold
  several datasets, and how `--multi` files them all.
- **[Design: rename and simplification](0001-rename-and-simplification.md)** —
  the rationale for the tool's shape.
- **[The columnar-specs engine](columnar-specs-engine.md)** — how bespoke
  fixed-shape tools are described declaratively.
- **[The held-out benchmark](benchmark-2026-08-12-generalisation.md)** — what
  happened the first time the engine met 50 outputs nobody wrote a parser for.

## The store model

Captures go to a **global git store** (`$PROVOST_HOME`, default `~/.provost`)
so you can capture from any directory. `provost control <dir>` makes a
directory its own instance: captures run inside it route there, and each
commit snapshots the directory's contents as context. A mkdir-based lock
serialises concurrent writers, so the store may be shared.

## License

GPL-3.0-or-later. Source, issues, and changelog live in the
[repository](https://github.com/MartinGallagher-code/provost).
