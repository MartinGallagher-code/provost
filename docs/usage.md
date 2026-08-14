# Usage

Everything `provost` does, from `provost help`. The man page
(`man/provost.1` in the repository, installed with the wheel) carries the same
content in roff form.

## Capturing

```console
$ provost run [--] <cmd> [args...]     # run a command, capture its output
$ cmd | provost                        # inject stdin (captures in the background)
$ provost FILE                         # inject a file instead of stdin
```

Inject flags:

| flag | effect |
|---|---|
| `--sync` / `--wait` | capture in the foreground and print the resulting dataset and `#N` range |
| `--silent` | no output on success |
| `--min-confidence N` | commit threshold, 0–100 (default 50) |
| `--plugin-dir DIR` | add an extra strategy directory to detection |
| `--multi` | file **every** dataset the input holds instead of one winner |

By default the capture runs in a detached background process and the prompt
returns at once; results appear in `provost log` shortly after.

## Browsing the store

```console
$ provost ls                     # list datasets
$ provost show NAME              # present a dataset (leading #N = row index)
$ provost log                    # list captures (the git history)
$ provost source <#N>            # the original input behind row #N
$ provost stats NAME [args]      # statistics on a dataset (--all for everything)
$ provost triage                 # low-confidence / unmatched bucket
$ provost restore <id|latest>    # bring a capture's commit back up
$ provost rm [-f] [--no-purge] NAME...
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

## Environment variables

| variable | meaning | default |
|---|---|---|
| `PROVOST_HOME` | global store dir | `~/.provost` |
| `PROVOST_WORKSPACE` | explicit store override (wins over `PROVOST_HOME`) | — |
| `PROVOST_MIN_CONFIDENCE` | commit threshold 0–100 | `50` |
| `PROVOST_PLUGIN_DIR` | extra strategy dir for detection | — |
| `PROVOST_ASYNC` | background capture (`0` or `--sync` for foreground) | `1` |
| `PROVOST_MULTI` | file every dataset an input holds (same as `--multi`) | `0` |
| `PROVOST_MAX_INPUT` | max input bytes | `10485760` |
| `PROVOST_LOCK_TIMEOUT` | seconds to wait for the store lock | `30` |

## Multiple datasets per input (`--multi`)

Some reports hold more than one kind of data — a key/value block, a table, and
a banner or comment run that is best left alone. The default one-winner capture
keeps whichever the engine ranks first and drops the rest; `--multi` splits the
input, parses each part on its own terms (a kv block and a table can even use
different delimiters), and files each as its own dataset under **one** capture.

Datasets are named by their winning strategy, so two parts that parse the same
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
