# Usage

Everything `provost` does, from `provost help`. The man page
(`man/provost.1` in the repository, installed with the wheel) carries the same
content in roff form.

## Capturing

```console
$ provost run [--] <cmd> [args...]     # run a command, file its output as dataset <cmd>
$ cmd | provost                        # inject stdin (dataset named after the parser)
$ provost FILE                         # inject a file instead of stdin
```

`provost run df -h` files into a dataset called `df` — wrappers such as `sudo`,
`env`, `nice` and `timeout` are looked through, so `sudo df -h` is `df` too.
Injected input has no command, so it is named after the parser that recognised
it (`csv`, `json-array`, `aligned-columns`, …); `--name` sets the name for either.

Capture flags (for `run` and inject):

| flag | effect |
|---|---|
| `--name NAME` | file into dataset `NAME` (letters, digits, `.`, `_`, `-`) |
| `--sync` / `--wait` | capture in the foreground and print the resulting dataset and `#N` range |
| `--async` | capture in a detached background process |
| `-q` / `--silent` | no output on success |
| `--min-confidence N` | commit threshold, 0–100 (default 50) |
| `--plugin-dir DIR` | add an extra strategy directory to detection |
| `--multi` | file **every** dataset the input holds instead of one winner |

At an interactive terminal the capture runs in the background and the prompt
returns at once; in a script or pipeline (stderr not a terminal) it runs in the
foreground, so `cmd | provost; provost show …` sees the result. A background
capture that fails is recorded in the store: the next provost command warns
about it, and `provost log --failed` lists it with the kept input and log.

## Browsing the store

```console
$ provost ls                     # list datasets
$ provost show NAME              # present a dataset (leading #N = row index)
$ provost log [--failed]         # list captures (the git history) / failed background ones
$ provost source <#N>            # the original input behind row #N
$ provost stats NAME [args]      # statistics on a dataset (--all for everything)
$ provost triage                 # low-confidence / unmatched bucket
$ provost restore <id|latest>    # bring a capture's commit back up
$ provost rm [-f] [--no-purge] NAME...   # captures are purged only when no dataset still uses them
```

## Instances and portability

```console
$ provost control [<dir>]        # make <dir> its own capture instance
$ provost uncontrol [<dir>]      # release a controlled directory
$ provost instances              # list controlled directories
$ provost export [<file>]        # bundle the store into a portable file
$ provost import <file> [<dest>] # reconstitute a bundle elsewhere
$ provost doctor                 # check engine + store
```

Captures go to a **global git store** — `$PROVOST_HOME`, or `~/.provost` if
unset — so you can capture from any directory. `provost control <dir>` makes
`<dir>` its own instance (`<dir>/.provost`): captures run inside it (or a
subdirectory) route there, and each commit snapshots the directory's contents
as context. Resolution order: `PROVOST_WORKSPACE` override, else the nearest
controlled directory walking up from the current directory, else the global
store.

While `provost restore <id>` has an old capture checked out, new captures and
`rm` are refused until `provost restore latest`.

A shared store (a group-writable `PROVOST_HOME`) is supported: a lock serialises
writers across users, and provost refuses a store whose `.git/config` others can
write if it sets anything beyond git's own keys — filter drivers, pagers and
includes can make git run programs as whoever captures next.

## Environment variables

| variable | meaning | default |
|---|---|---|
| `PROVOST_HOME` | global store dir | `~/.provost` |
| `PROVOST_WORKSPACE` | explicit store override (wins over `PROVOST_HOME`) | — |
| `PROVOST_MIN_CONFIDENCE` | commit threshold 0–100 | `50` |
| `PROVOST_PLUGIN_DIR` | extra strategy dir for detection | — |
| `PROVOST_ASYNC` | `1` always background, `0` always foreground, unset = background only at a terminal | unset |
| `PROVOST_MULTI` | file every dataset an input holds (same as `--multi`) | `0` |
| `PROVOST_MAX_INPUT` | max input bytes, for inject and `run` | `10485760` |
| `PROVOST_LOCK_TIMEOUT` | seconds to wait for the store lock | `30` |
| `PROVOST_LOCK_MAX_AGE` | seconds after which a lock is presumed stale | `3600` |
| `PROVOST_RECONCILE_OVERLAP` | % column overlap needed to merge a changed schema into a dataset instead of splitting `NAME.v2` | `60` |
| `PROVOST_QUIET` | `1` suppresses progress/ok messages (same as `--silent`) | `0` |

Numeric settings must be whole numbers; anything else is rejected at startup.

## Multiple datasets per input (`--multi`)

Some reports hold more than one kind of data — a key/value block, a table, and
a banner or comment run that is best left alone. The default one-winner capture
keeps whichever the engine ranks first and drops the rest; `--multi` splits the
input, parses each part on its own terms (a kv block and a table can even use
different delimiters), and files each as its own dataset under **one** capture.

Datasets are named by their winning strategy (prefixed `NAME.` when `--name`
or `run` supplies one), so two parts that parse the same
way but differ in shape land in `NAME` and `NAME.v2`. Row indices (`#N`) run
consecutively across them and `provost source N` still returns the whole
original input. `provost log` shows the comma-joined list; the capture's
`meta.tsv` records `datasets` (how many) and `dataset_rows` (each one's range).

See [the multi-dataset design note](0003-multi-dataset.md) for the rationale
and the scoring machinery behind the split.

## Metadata prologue

A leading run of `#%` lines on injected input is treated as capture context,
not data: it is peeled off before format detection (so it cannot corrupt a
parse), stored with the capture (`context.txt`), and shown verbatim by
`provost source`. Wrappers can prepend context unconditionally.
