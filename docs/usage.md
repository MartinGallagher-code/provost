# Usage

Everything `provost` does, from `provost help advanced` (`provost help` is the short version). The man page
(`man/provost.1` in the repository, installed with the wheel) carries the same
content in roff form.

## Capturing

```console
$ provost run [--] <cmd> [args...]     # run a command, file its output as dataset <cmd>
$ cmd | provost                        # inject stdin (dataset named after the parser)
$ provost FILE                         # inject a file instead of stdin
$ provost batch FILE... [--from LIST]  # inject many files: a capture each, one commit
$ provost listen <cmd>                 # file <cmd>'s output every time it runs (unlisten to stop)
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
| `--no-auto-multi` | hold a parse the quality gate rejects without first trying to segment it (`--auto-multi`, the default, tries) |
| `--context-columns` | make each `key=value` word of a `#%` prologue a column on every row (see [Metadata prologue](#metadata-prologue)) |

At an interactive terminal the capture runs in the background and the prompt
returns at once; in a script or pipeline (stderr not a terminal) it runs in the
foreground, so `cmd | provost; provost show …` sees the result. A background
capture that fails is recorded in the store: the next provost command warns
about it, and `provost log --failed` lists it with the kept input and log.

## Browsing the store

```console
$ provost ls                     # list datasets
$ provost show NAME              # present a dataset ('#', 'capture', 'n' lead each row)
$ provost show NAME --capture ID # only the rows capture ID filed
$ provost show NAME --at ID      # the dataset as it stood just after capture ID
$ provost search PATTERN [NAME]  # git grep over the rows (--output, --files, --at ID)
$ provost log [--failed]         # list captures (the git history) / failed background ones
$ provost source <#N | ID>       # the original input behind row #N, or a capture
$ provost diff [NAME] [A [B]]    # rows and run files that changed between two captures
$ provost stats NAME [args]      # statistics on a dataset (--all for everything)
$ provost triage                 # low-confidence / unmatched bucket
$ provost restore <id|latest>    # bring a capture's commit back up
$ provost prev / provost next    # step the store back / forward one capture
$ provost rm [-f] [--no-purge] NAME...   # captures are purged only when no dataset still uses them
```

Every row carries `#` (its number in the store, `provost source N`),
`capture` (the capture it came from, `provost source c0007`) and, for
records, `n` (its place within that capture). An ID is `c0007`, `7` or
`capture-c0007`.

## Instances and portability

```console
$ provost control [<dir>]        # make <dir> its own capture instance; each run keeps its files
$ provost files [ID] [PATH]      # those files as a capture kept them (--to DIR writes them out)
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
| `PROVOST_CONTEXT_COLUMNS` | `1` = each `key=value` word of a `#%` prologue becomes a column on the capture's rows (same as `--context-columns`) | `0` |
| `PROVOST_AUTO_MULTI` | `1` = segment a parse the quality gate would hold, when the parts are clearly better; `0` = hold it (same as `--no-auto-multi`) | `1` |
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

**Auto-multi.** Without `--multi`, provost still segments a capture when the
quality gate would otherwise hold its single parse for low coverage or low
consistency — but only when the split is clearly better: two or more parts,
each passing the gate on its own, together keeping at least the gate's
coverage and 10 points more than the single parse, no part a table under
positional `A`/`B`/`C` columns only, and no shattering into fragments.
Otherwise the capture is held as before, with the reason. The ok line says it
segmented and why; `meta.tsv` records `auto_multi`, the held single parse's
`single_*` measures, and each part's `dataset_coverage` /
`dataset_consistency`. With a `NAME`, the part whose columns match the single
parse's keeps dataset `NAME`, so repeated captures of one command keep their
rows together whether or not a capture segments. `PROVOST_AUTO_MULTI=0` (or
`--no-auto-multi`) turns it off.

See [the multi-dataset design note](0003-multi-dataset.md) for the rationale
and the scoring machinery behind the split.

## Metadata prologue

A leading run of `#%` lines on injected input is treated as capture context,
not data: it is peeled off before format detection (so it cannot corrupt a
parse), stored with the capture (`context.txt`), and shown verbatim by
`provost source`. Wrappers can prepend context unconditionally.

**Context columns.** With `--context-columns` (or `PROVOST_CONTEXT_COLUMNS=1`)
every `key=value` word in the prologue is also put on each row the capture
files, after `#` and `capture`:

```console
$ printf '#%% host=web03 rack=r2\nName,Load\nweb,0.5\n' | provost --sync --context-columns --name load
$ provost show load
#  capture  host   rack  n  Name  Load
1  c0001    web03  r2    1  web   0.5
```

Keys are letters, digits, `_`, `.` and `-`, starting with a letter or `_`;
the last value of a repeated key wins, and words that are not `key=value` stay
context only. A data column of the same name keeps it, and the context column
becomes `_host` — the rule `capture` already follows, so a by-name union never
merges the two. A capture held in `unsorted` is kept as it came, one raw
column.

## Batch capture

```console
$ provost batch [options] FILE... [--from LIST]
```

Each file is a capture of its own, exactly as `provost FILE` would make it —
its own id, its own `provost source`, its own `capture-<id>` tag — but the
inputs are parsed in parallel and filed under one hold of the store lock as
**one** commit. The parse is the slow half of a capture and needs no lock, so
fifty captures in a row each pay for their own parse and commit, while fifty
in a batch share the CPUs and one commit (40 small inputs: 13 s against 55 s
on 4 CPUs). The lock is held about 50 ms an input; other writers wait for it
up to `PROVOST_LOCK_TIMEOUT`.

- Capture ids follow the order the files were named, whichever parsed first.
  Each capture's `meta.tsv` records its `input` path and its `batch` (the id
  range).
- `--name NAME` applies to the files after it, until the next `--name`.
- `--from LIST` reads more files from `LIST` (`-` for stdin), one a line:
  `PATH`, or `NAME<TAB>PATH` for a file of its own name. Blank lines and lines
  starting `#` are skipped.
- `-j N` / `--jobs N` parses at most `N` files at a time (default: the CPUs,
  at most 16). `--llm` parses one at a time, so a template Claude writes for a
  tool is written once, not once per file.
- Every file is checked before anything is filed. An empty file is skipped
  with a note; one that is too large or fails to parse is reported and the
  rest are still filed. The exit status is 1 if any file was not captured.

For a wrapper that captures a fleet, write one file per host, open each with
`#% host=NAME` (and anything else worth a column), and pass
`--context-columns`: every row then says which host it came from, and
`provost source` still shows each host's answer on its own.
